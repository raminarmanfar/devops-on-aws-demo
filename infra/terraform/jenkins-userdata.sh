#!/bin/bash
# Jenkins bootstrap script – runs once on first boot (Amazon Linux 2023)
set -euo pipefail

# ── System update ──────────────────────────────────────────────────────────────
dnf update -y

# ── Java 17 (Jenkins requirement) ─────────────────────────────────────────────
dnf install -y java-17-amazon-corretto-headless git

# ── Jenkins ────────────────────────────────────────────────────────────────────
curl -o /etc/yum.repos.d/jenkins.repo \
    https://pkg.jenkins.io/redhat-stable/jenkins.repo
rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io-2023.key
dnf install -y jenkins
systemctl enable --now jenkins

# ── Docker ─────────────────────────────────────────────────────────────────────
dnf install -y docker
systemctl enable --now docker
usermod -aG docker jenkins

# ── kubectl ────────────────────────────────────────────────────────────────────
KUBECTL_VERSION=$(curl -sL https://dl.k8s.io/release/stable.txt)
curl -sLo /usr/local/bin/kubectl \
    "https://dl.k8s.io/release/$${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
chmod +x /usr/local/bin/kubectl

# ── AWS CLI (already present on AL2023, ensure latest) ────────────────────────
dnf install -y aws-cli

# ── SSM Agent (pre-installed on AL2023, ensure running) ───────────────────────
systemctl enable --now amazon-ssm-agent || true

# ── Configure kubectl for EKS ──────────────────────────────────────────────────
# The instance role gives Jenkins permission to call eks:DescribeCluster
mkdir -p /var/lib/jenkins/.kube
aws eks update-kubeconfig \
    --region "${aws_region}" \
    --name   "${cluster_name}" \
    --kubeconfig /var/lib/jenkins/.kube/config || true
chown -R jenkins:jenkins /var/lib/jenkins/.kube

echo "Bootstrap complete. Jenkins is running on port 8080."
echo "Initial admin password: $(cat /var/lib/jenkins/secrets/initialAdminPassword 2>/dev/null || echo 'not yet generated – wait 2 min')"
