pipeline {
    agent any

    environment {
        AWS_REGION      = 'eu-central-1'
        BACKEND_REPO    = 'devops-demo/backend'
        FRONTEND_REPO   = 'devops-demo/frontend'
        GIT_CREDENTIALS = 'github-credentials'   // Jenkins credential ID
    }

    stages {

        stage('Setup') {
            steps {
                script {
                    env.IMAGE_TAG = sh(
                        script: 'git rev-parse --short HEAD',
                        returnStdout: true
                    ).trim()
                    env.AWS_ACCOUNT_ID = sh(
                        script: 'aws sts get-caller-identity --query Account --output text',
                        returnStdout: true
                    ).trim()
                    env.ECR_REGISTRY    = "${env.AWS_ACCOUNT_ID}.dkr.ecr.${env.AWS_REGION}.amazonaws.com"
                    env.BACKEND_IMAGE   = "${env.ECR_REGISTRY}/${env.BACKEND_REPO}"
                    env.FRONTEND_IMAGE  = "${env.ECR_REGISTRY}/${env.FRONTEND_REPO}"
                }
                echo "Image tag  : ${env.IMAGE_TAG}"
                echo "ECR registry: ${env.ECR_REGISTRY}"
            }
        }

        stage('Test Backend') {
            steps {
                dir('backend') {
                    sh './mvnw test'
                }
            }
        }

        stage('Build Backend') {
            steps {
                dir('backend') {
                    sh './mvnw package -DskipTests -q'
                }
            }
        }

        stage('Test & Build Frontend') {
            steps {
                dir('frontend') {
                    sh 'npm ci --quiet'
                    sh 'npm test -- --run'
                    sh 'npm run build'
                }
            }
        }

        stage('Login to ECR') {
            steps {
                sh '''
                    aws ecr get-login-password --region ${AWS_REGION} \
                        | docker login --username AWS --password-stdin ${ECR_REGISTRY}
                '''
            }
        }

        stage('Build & Push Docker Images') {
            parallel {
                stage('Backend Image') {
                    steps {
                        sh '''
                            docker build \
                                -t ${BACKEND_IMAGE}:${IMAGE_TAG} \
                                -t ${BACKEND_IMAGE}:latest \
                                ./backend
                            docker push ${BACKEND_IMAGE}:${IMAGE_TAG}
                            docker push ${BACKEND_IMAGE}:latest
                        '''
                    }
                }
                stage('Frontend Image') {
                    steps {
                        sh '''
                            docker build \
                                -t ${FRONTEND_IMAGE}:${IMAGE_TAG} \
                                -t ${FRONTEND_IMAGE}:latest \
                                ./frontend
                            docker push ${FRONTEND_IMAGE}:${IMAGE_TAG}
                            docker push ${FRONTEND_IMAGE}:latest
                        '''
                    }
                }
            }
        }

        stage('Update K8s Manifests') {
            steps {
                withCredentials([usernamePassword(
                    credentialsId: env.GIT_CREDENTIALS,
                    usernameVariable: 'GIT_USER',
                    passwordVariable: 'GIT_TOKEN'
                )]) {
                    sh '''
                        git config user.email "jenkins@ci.local"
                        git config user.name  "Jenkins CI"

                        # Stamp new image tags in deployment manifests
                        sed -i "s|image: .*devops-demo/backend.*|image: ${BACKEND_IMAGE}:${IMAGE_TAG}|" \
                            infra/kubernetes/backend/deployment.yaml
                        sed -i "s|image: .*devops-demo/frontend.*|image: ${FRONTEND_IMAGE}:${IMAGE_TAG}|" \
                            infra/kubernetes/frontend/deployment.yaml

                        git add infra/kubernetes/backend/deployment.yaml \
                                infra/kubernetes/frontend/deployment.yaml

                        # Only commit when there is a real change
                        git diff --staged --quiet || \
                            git commit -m "ci: deploy image tag ${IMAGE_TAG} [skip ci]"

                        REMOTE_URL=$(git remote get-url origin | sed 's|https://||')
                        git push https://${GIT_USER}:${GIT_TOKEN}@${REMOTE_URL} HEAD:main
                    '''
                }
            }
        }
    }

    post {
        always {
            sh 'docker system prune -f --volumes 2>/dev/null || true'
        }
        success {
            echo "SUCCESS: image ${env.IMAGE_TAG} pushed. ArgoCD will sync to EKS."
        }
        failure {
            echo "PIPELINE FAILED – check logs above."
        }
    }
}
