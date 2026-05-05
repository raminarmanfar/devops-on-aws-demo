#!/bin/bash
# Jenkins bootstrap script – runs once on first boot (Amazon Linux 2023)
# Note: do NOT use set -e; we handle errors individually so SSM always starts.

exec > >(tee /var/log/jenkins-bootstrap.log | logger -t jenkins-bootstrap) 2>&1
echo "=== Bootstrap started at $(date -u) ==="

# ── SSM Agent first – ensures we can always connect for debugging ──────────────
systemctl enable --now amazon-ssm-agent || true

# ── System update ──────────────────────────────────────────────────────────────
dnf update -y

# ── Java 21 (Jenkins 2.463+ requires Java 21) ─────────────────────────────────
dnf install -y java-21-amazon-corretto-headless git

# ── Jenkins ────────────────────────────────────────────────────────────────────
curl -fSLo /etc/yum.repos.d/jenkins.repo \
    https://pkg.jenkins.io/redhat-stable/jenkins.repo
rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io-2023.key
dnf install -y jenkins
systemctl enable jenkins
# Start Jenkins and wait up to 60s for it to become ready
systemctl start jenkins || true
for i in $(seq 1 12); do
  sleep 5
  if systemctl is-active --quiet jenkins; then
    echo "Jenkins is running after $((i*5))s"
    break
  fi
  echo "Waiting for Jenkins... attempt $i"
  systemctl start jenkins || true
done

# ── Docker ─────────────────────────────────────────────────────────────────────
dnf install -y docker
systemctl enable --now docker
usermod -aG docker jenkins

# ── kubectl ────────────────────────────────────────────────────────────────────
KUBECTL_VERSION=$(curl -sL https://dl.k8s.io/release/stable.txt)
curl -sLo /usr/local/bin/kubectl \
    "https://dl.k8s.io/release/$${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
chmod +x /usr/local/bin/kubectl

# ── AWS CLI (already present on AL2023) ───────────────────────────────────────
dnf install -y aws-cli || true

# ── Configure kubectl for EKS ──────────────────────────────────────────────────
mkdir -p /var/lib/jenkins/.kube
aws eks update-kubeconfig \
    --region "${aws_region}" \
    --name   "${cluster_name}" \
    --kubeconfig /var/lib/jenkins/.kube/config || true
chown -R jenkins:jenkins /var/lib/jenkins/.kube

echo "=== Bootstrap complete at $(date -u) ==="
PASS=$(cat /var/lib/jenkins/secrets/initialAdminPassword 2>/dev/null || echo 'not yet generated')
echo "Initial admin password: $PASS"
