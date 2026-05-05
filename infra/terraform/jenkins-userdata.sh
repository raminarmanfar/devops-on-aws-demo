#!/bin/bash
# Jenkins bootstrap script – runs once on first boot (Amazon Linux 2023)
# No set -e; handle errors individually so boot always completes cleanly.

exec > >(tee /var/log/jenkins-bootstrap.log) 2>&1
echo "=== Bootstrap started at $(date -u) ==="

# ── SSM Agent – start first for remote debugging ───────────────────────────────
systemctl enable --now amazon-ssm-agent || true

# ── System update ──────────────────────────────────────────────────────────────
dnf update -y

# ── EC2 Instance Connect (SSH debugging) ───────────────────────────────────────
dnf install -y ec2-instance-connect || true

# ── Java 21 (Jenkins 2.463+ requires Java 21) ─────────────────────────────────
dnf install -y java-21-amazon-corretto-headless git

# ── Jenkins ────────────────────────────────────────────────────────────────────
curl -fSLo /etc/yum.repos.d/jenkins.repo \
    https://pkg.jenkins.io/redhat-stable/jenkins.repo
rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io-2023.key
dnf install -y jenkins

# ── Disable setup wizard, configure Jenkins via Groovy ────────────────────────
# Set JAVA_OPTS to skip the setup wizard
echo 'JENKINS_JAVA_OPTS="-Djava.awt.headless=true -Djenkins.install.runSetupWizard=false"' \
    >> /etc/sysconfig/jenkins

# Create admin user and configure security via Groovy init script
mkdir -p /var/lib/jenkins/init.groovy.d
cat > /var/lib/jenkins/init.groovy.d/admin-setup.groovy << 'GROOVY'
#!groovy
import jenkins.model.*
import hudson.security.*
import jenkins.install.InstallState

def instance = Jenkins.getInstance()

// Mark setup as complete
instance.installState = InstallState.INITIAL_SETUP_COMPLETED

// Create admin user with a known password
def hudsonRealm = new HudsonPrivateSecurityRealm(false)
hudsonRealm.createAccount('admin', 'DevOpsDemo2024!')
instance.setSecurityRealm(hudsonRealm)

// Full control for logged-in users
def strategy = new FullControlOnceLoggedInAuthorizationStrategy()
strategy.setAllowAnonymousRead(false)
instance.setAuthorizationStrategy(strategy)

instance.save()

// Self-delete so it doesn't re-run
new File(this.class.protectionDomain.codeSource.location.path).delete()
GROOVY

chown -R jenkins:jenkins /var/lib/jenkins/init.groovy.d /etc/sysconfig/jenkins 2>/dev/null || true

# ── Start Jenkins ──────────────────────────────────────────────────────────────
systemctl enable jenkins
systemctl start jenkins

# ── Docker ─────────────────────────────────────────────────────────────────────
dnf install -y docker
systemctl enable --now docker
usermod -aG docker jenkins

# ── kubectl ────────────────────────────────────────────────────────────────────
KUBECTL_VERSION=$(curl -sL https://dl.k8s.io/release/stable.txt)
curl -sLo /usr/local/bin/kubectl \
    "https://dl.k8s.io/release/$${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
chmod +x /usr/local/bin/kubectl

# ── Configure kubectl for EKS ──────────────────────────────────────────────────
mkdir -p /var/lib/jenkins/.kube
aws eks update-kubeconfig \
    --region "${aws_region}" \
    --name   "${cluster_name}" \
    --kubeconfig /var/lib/jenkins/.kube/config || true
chown -R jenkins:jenkins /var/lib/jenkins/.kube

# ── Restart SSM after full init ────────────────────────────────────────────────
systemctl restart amazon-ssm-agent || true

echo "=== Bootstrap complete at $(date -u) ==="
echo "Jenkins admin credentials: admin / DevOpsDemo2024!"
