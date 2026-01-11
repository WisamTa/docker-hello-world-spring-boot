pipeline {
    agent any

    environment {
        REGISTRY = 'europe-docker.pkg.dev'
        GCP_PROJECT = 'curamet-onboarding'
        ARTIFACT_REPO = 'spring-boot'
        IMAGE_NAME = 'spring-boot-hello'
        IMAGE_TAG = 'spring'
        IMAGE_URL = "${REGISTRY}/${GCP_PROJECT}/${ARTIFACT_REPO}/${IMAGE_NAME}:${IMAGE_TAG}"
        GKE_CLUSTER = 'autopilot-cluster-1'
        GKE_REGION = 'europe-north1'
        HELM_RELEASE_NAME = 'spring-release'
        HELM_NAMESPACE = 'spring'
        HELM_CHART_PATH = './first-chart'
    }

    parameters {
        booleanParam(name: 'SKIP_TESTS', defaultValue: false, description: 'Skip Maven tests')
    }

    options {
        buildDiscarder(logRotator(numToKeepStr: '10'))
        timeout(time: 1, unit: 'HOURS')
        timestamps()
    }

    stages {
        stage('Checkout') {
            steps {
                script {
                    echo "========== Checking out code =========="
                    checkout scm
                }
            }
        }

        stage('Build & Test') {
            steps {
                script {
                    echo "========== Building with Maven =========="
                    sh '''
                        java -version
                        mvn --version
                        mvn clean package ${params.SKIP_TESTS ? '-DskipTests' : ''}
                    '''
                }
            }
        }

        stage('Build Docker Image') {
            steps {
                script {
                    echo "========== Building Docker Image =========="
                    sh '''
                        docker build -t ${IMAGE_URL} .
                        docker images | grep spring-boot-hello
                    '''
                }
            }
        }

        stage('Authenticate GCP & Push Image') {
            steps {
                script {
                    echo "========== Authenticating to GCP =========="
                    withCredentials([file(credentialsId: 'gcp-service-account-key', variable: 'GCP_KEY_FILE')]) {
                        sh '''
                            # Authenticate with GCP
                            gcloud auth activate-service-account --key-file=${GCP_KEY_FILE}
                            gcloud config set project ${GCP_PROJECT}
                            
                            # Configure Docker for Artifact Registry
                            gcloud auth configure-docker ${REGISTRY} --quiet
                            
                            # Push image to Artifact Registry
                            echo "========== Pushing Docker Image to Artifact Registry =========="
                            docker push ${IMAGE_URL}
                            echo "Image pushed: ${IMAGE_URL}"
                        '''
                    }
                }
            }
        }

        stage('Get GKE Credentials') {
            steps {
                script {
                    echo "========== Getting GKE Cluster Credentials =========="
                    withCredentials([file(credentialsId: 'gcp-service-account-key', variable: 'GCP_KEY_FILE')]) {
                        sh '''
                            gcloud auth activate-service-account --key-file=${GCP_KEY_FILE}
                            gcloud config set project ${GCP_PROJECT}
                            gcloud container clusters get-credentials ${GKE_CLUSTER} \
                                --region ${GKE_REGION} \
                                --project ${GCP_PROJECT}
                        '''
                    }
                }
            }
        }

        stage('Install Helm') {
            steps {
                script {
                    echo "========== Installing Helm =========="
                    sh '''
                        which helm || (curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash)
                        helm version
                    '''
                }
            }
        }

        stage('Create Namespace') {
            steps {
                script {
                    echo "========== Creating Kubernetes Namespace =========="
                    sh '''
                        kubectl create namespace ${HELM_NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -
                    '''
                }
            }
        }

        stage('Helm Lint') {
            steps {
                script {
                    echo "========== Linting Helm Chart =========="
                    sh '''
                        helm lint ${HELM_CHART_PATH}
                    '''
                }
            }
        }

        stage('Helm Dry-Run') {
            steps {
                script {
                    echo "========== Running Helm Dry-Run =========="
                    sh '''
                        helm upgrade ${HELM_RELEASE_NAME} ${HELM_CHART_PATH} \
                            --namespace ${HELM_NAMESPACE} \
                            --install \
                            --dry-run \
                            --debug
                    '''
                }
            }
        }

        stage('Deploy with Helm') {
            steps {
                script {
                    echo "========== Deploying with Helm =========="
                    sh '''
                        helm upgrade ${HELM_RELEASE_NAME} ${HELM_CHART_PATH} \
                            --namespace ${HELM_NAMESPACE} \
                            --install \
                            --wait=false
                        
                        echo "Helm release status:"
                        helm status ${HELM_RELEASE_NAME} -n ${HELM_NAMESPACE}
                    '''
                }
            }
        }

        stage('Verify Deployment') {
            steps {
                script {
                    echo "========== Verifying Deployment =========="
                    sh '''
                        echo "=== Pods Status ==="
                        kubectl get pods -n ${HELM_NAMESPACE}
                        
                        echo -e "\n=== Services ==="
                        kubectl get svc -n ${HELM_NAMESPACE}
                        
                        echo -e "\n=== Deployment Status ==="
                        kubectl get deployment -n ${HELM_NAMESPACE}
                    '''
                }
            }
        }

        stage('Wait for Rollout') {
            steps {
                script {
                    echo "========== Waiting for Rollout to Complete =========="
                    sh '''
                        kubectl rollout status deployment/spring-hello-world \
                            --namespace ${HELM_NAMESPACE} \
                            --timeout=5m || true
                    '''
                }
            }
        }

        stage('Show Helm History') {
            steps {
                script {
                    echo "========== Helm Release History =========="
                    sh '''
                        helm history ${HELM_RELEASE_NAME} -n ${HELM_NAMESPACE}
                    '''
                }
            }
        }
    }

    post {
        always {
            script {
                echo "========== Build Completed =========="
                cleanWs()
            }
        }
        success {
            script {
                echo "========== Pipeline Succeeded =========="
            }
        }
        failure {
            script {
                echo "========== Pipeline Failed =========="
            }
        }
    }
}

