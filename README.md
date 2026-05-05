# DevOps on AWS Demo

A full-stack demo application with a complete GitOps CI/CD pipeline on AWS.

**Stack:** Spring Boot (Java 17) · Angular 21 · Jenkins · Amazon EKS · ArgoCD · Amazon ECR · Terraform

---

## Architecture

```
Developer
    │
    │  git push
    ▼
 GitHub ──────────────────────────────────────┐
    │                                         │
    │  webhook / poll                         │  ArgoCD watches
    ▼                                         │  infra/kubernetes/
 Jenkins (EC2)                                │
  · mvn test + package                        │
  · docker build + push → ECR                 │
  · update image tag in manifests             │
  · git push back to GitHub ─────────────────►│
                                              │
                                    ArgoCD (EKS)
                                     auto-sync
                                              │
                                    Kubernetes (EKS)
                              ┌───────────────┴──────────────┐
                              │         nginx Ingress         │
                              │  /api/* → backend pods :3000  │
                              │  /      → frontend pods :80   │
                              └───────────────────────────────┘
```

### Networking

```
VPC 10.0.0.0/16  (eu-central-1)
├── Public subnets  10.0.1.0/24 · 10.0.2.0/24
│   ├── Jenkins EC2 (Elastic IP, port 8080)
│   ├── NAT Gateway
│   └── AWS Network Load Balancer (nginx ingress)
│
└── Private subnets  10.0.10.0/24 · 10.0.11.0/24
    └── EKS worker nodes
        ├── backend pods   (Spring Boot)
        ├── frontend pods  (nginx + Angular)
        └── ArgoCD pods
```

---

## Repository structure

```
devops-on-aws-demo/
├── backend/                        # Spring Boot application
│   ├── src/
│   ├── Dockerfile                  # Multi-stage: JDK build → JRE runtime
│   └── pom.xml
│
├── frontend/                       # Angular application
│   ├── src/
│   ├── Dockerfile                  # Multi-stage: Node build → nginx serve
│   ├── nginx.conf                  # SPA routing + asset caching
│   └── proxy.conf.json             # Dev proxy: /api → localhost:3000
│
├── infra/
│   ├── terraform/                  # All AWS infrastructure (IaC)
│   │   ├── providers.tf
│   │   ├── variables.tf
│   │   ├── vpc.tf
│   │   ├── security-groups.tf
│   │   ├── iam.tf
│   │   ├── ecr.tf
│   │   ├── eks.tf
│   │   ├── jenkins-ec2.tf
│   │   ├── jenkins-userdata.sh
│   │   ├── argocd.tf
│   │   └── outputs.tf
│   │
│   └── kubernetes/                 # K8s manifests (watched by ArgoCD)
│       ├── backend/
│       │   ├── deployment.yaml
│       │   └── service.yaml
│       ├── frontend/
│       │   ├── deployment.yaml
│       │   └── service.yaml
│       ├── ingress.yaml
│       └── argocd-apps/
│           ├── backend-app.yaml
│           └── frontend-app.yaml
│
└── Jenkinsfile                     # CI pipeline definition
```

---

## Prerequisites

| Tool | Version | Purpose |
|---|---|---|
| [Terraform](https://developer.hashicorp.com/terraform/install) | ≥ 1.6 | Provision AWS infrastructure |
| [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html) | v2 | Authenticate to AWS |
| [kubectl](https://kubernetes.io/docs/tasks/tools/) | ≥ 1.31 | Interact with EKS |
| [Docker](https://docs.docker.com/get-docker/) | any | Build images locally (optional) |
| [Java 17](https://adoptium.net/) | 17 | Run backend locally |
| [Node.js](https://nodejs.org/) | 20 | Run frontend locally |

---

## Local development

### Backend

```bash
cd backend
./mvnw spring-boot:run
# API available at http://localhost:3000/api/hello
```

### Frontend

```bash
cd frontend
npm install
npm start
# App available at http://localhost:4200
# Requests to /api are proxied to http://localhost:3000 via proxy.conf.json
```

---

## AWS deployment

### 1. Configure AWS credentials

```bash
aws configure
# Enter: Access Key ID, Secret Access Key, region (eu-central-1), output format (json)
```

### 2. (Optional) Create an EC2 key pair for SSH access to Jenkins

In the AWS Console → EC2 → Key Pairs → Create key pair. Save the `.pem` file.

### 3. Provision infrastructure with Terraform

```bash
cd infra/terraform
terraform init
terraform plan                  # review what will be created
terraform apply                 # type 'yes' to confirm
```

> **Time:** ~15–20 minutes. The EKS cluster is the slowest resource.

#### Terraform variables (optional overrides)

Create a `terraform.tfvars` file to override defaults:

```hcl
aws_region             = "eu-central-1"
project_name           = "devops-demo"
environment            = "dev"
jenkins_key_pair_name  = "my-key-pair"       # optional, for SSH
jenkins_allowed_cidr   = "203.0.113.10/32"   # restrict to your IP
eks_node_desired_size  = 2
eks_node_instance_type = "t3.medium"
```

#### Resources created by Terraform

| Resource | Details |
|---|---|
| VPC | 10.0.0.0/16, 2 public + 2 private subnets |
| NAT Gateway | Single gateway for cost optimisation |
| ECR | `devops-demo/backend` and `devops-demo/frontend` |
| EKS Cluster | Kubernetes 1.31, managed node group (t3.medium) |
| Jenkins EC2 | t3.medium, Amazon Linux 2023, auto-bootstrapped |
| ArgoCD | Installed via Helm into EKS |
| nginx Ingress | Installed via Helm, backed by AWS Network Load Balancer |
| IAM Roles | Cluster, node group, and Jenkins roles (no hardcoded credentials) |

### 4. After `terraform apply`

Get the outputs:

```bash
terraform output
```

| Output | Use |
|---|---|
| `jenkins_url` | Open in browser to access Jenkins |
| `configure_kubectl` | Run this to point `kubectl` at your cluster |
| `ecr_backend_url` | ECR URL for the backend image |
| `ecr_frontend_url` | ECR URL for the frontend image |

Point `kubectl` at the new cluster:

```bash
aws eks update-kubeconfig --region eu-central-1 --name devops-demo-cluster
kubectl get nodes   # should show running nodes
```

### 5. Configure Jenkins

1. Open `http://<jenkins_ip>:8080`
2. Get the initial admin password:
   ```bash
   ssh -i your-key.pem ec2-user@<jenkins_ip>
   sudo cat /var/lib/jenkins/secrets/initialAdminPassword
   ```
3. Install suggested plugins
4. Add a GitHub credential:
   - **Dashboard → Manage Jenkins → Credentials → Add**
   - Kind: `Username with password`
   - Username: your GitHub username
   - Password: a [Personal Access Token](https://github.com/settings/tokens) with `repo` scope
   - ID: `github-credentials`
5. Create a Pipeline job pointing at this repository, using `Jenkinsfile`

### 6. Register ArgoCD applications

```bash
kubectl apply -f infra/kubernetes/argocd-apps/backend-app.yaml
kubectl apply -f infra/kubernetes/argocd-apps/frontend-app.yaml
```

Get the ArgoCD UI load balancer URL:

```bash
kubectl get svc argocd-server -n argocd
```

Get the initial ArgoCD admin password:

```bash
kubectl get secret argocd-initial-admin-secret -n argocd \
  -o jsonpath="{.data.password}" | base64 -d
```

Log in at `http://<argocd-lb-url>` with username `admin`.

---

## CI/CD pipeline (Jenkinsfile)

Every push to `main` triggers:

```
1. Setup         – read git SHA, discover AWS account ID
2. Test Backend  – mvn test
3. Build Backend – mvn package (produces JAR)
4. Login to ECR  – using Jenkins IAM instance role
5. Build & Push  – docker build + push for backend and frontend (parallel)
6. Update K8s    – sed new image tag into deployment YAMLs, git push
```

ArgoCD detects the manifest change within ~3 minutes and performs a rolling deployment to EKS.

---

## Kubernetes workloads

| Workload | Replicas | Port | Service type |
|---|---|---|---|
| backend | 2 | 3000 | ClusterIP |
| frontend | 2 | 80 | ClusterIP |
| nginx Ingress | — | 80/443 | LoadBalancer |

Traffic routing via nginx Ingress:

| Path | Destination |
|---|---|
| `/api/*` | `backend-service:3000` |
| `/` | `frontend-service:80` |

---

## Tearing down

To destroy all AWS resources and avoid ongoing charges:

```bash
cd infra/terraform
terraform destroy
```

> **Note:** ECR images must be deleted manually before `terraform destroy` can remove the repositories, or set `force_delete = true` in `ecr.tf`.

---

## Security notes

- Jenkins uses an **IAM instance role** — no AWS credentials stored on disk
- EKS worker nodes are in **private subnets** — not directly reachable from the internet
- ECR has **image scanning on push** enabled
- Restrict `jenkins_allowed_cidr` to your own IP in production
- Rotate the ArgoCD admin password after first login
