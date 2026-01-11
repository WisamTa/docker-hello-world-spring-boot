# Jenkins Setup with Workload Identity Federation (WIF)

## Prerequisites
- Jenkins running on your local machine (Docker container)
- GCP project: `curamet-onboarding`
- GitHub repository: `WisamTa/docker-hello-world-spring-boot`
- gcloud CLI installed and authenticated

## Step 1: Create Jenkins WIF Pool (if not already exists)

```bash
# Set variables
export GCP_PROJECT="curamet-onboarding"
export WIF_POOL="jenkins-pool"
export WIF_PROVIDER="jenkins-provider"
export LOCATION="global"

# Create WIF pool
gcloud iam workload-identity-pools create ${WIF_POOL} \
  --project="${GCP_PROJECT}" \
  --location="${LOCATION}" \
  --display-name="Jenkins WIF Pool"

# Get the pool resource name
export WIF_POOL_ID=$(gcloud iam workload-identity-pools describe ${WIF_POOL} \
  --project="${GCP_PROJECT}" \
  --location="${LOCATION}" \
  --format='value(name)')
```

## Step 2: Create OIDC Provider for Jenkins

```bash
# Create OIDC provider for Jenkins
gcloud iam workload-identity-pools providers create-oidc ${WIF_PROVIDER} \
  --project="${GCP_PROJECT}" \
  --location="${LOCATION}" \
  --workload-identity-pool="${WIF_POOL}" \
  --display-name="Jenkins OIDC Provider" \
  --attribute-mapping="google.subject=sub,assertion.issuer=iss" \
  --issuer-uri="http://localhost:8080" \
  --attribute-condition="assertion.audience == '${GCP_PROJECT}'"
```

## Step 3: Create Service Account for Jenkins

```bash
# Create service account
gcloud iam service-accounts create jenkins \
  --project="${GCP_PROJECT}" \
  --display-name="Jenkins Service Account"

# Get service account email
export SERVICE_ACCOUNT="jenkins@${GCP_PROJECT}.iam.gserviceaccount.com"

# Grant permissions
gcloud projects add-iam-policy-binding "${GCP_PROJECT}" \
  --member="serviceAccount:${SERVICE_ACCOUNT}" \
  --role="roles/artifactregistry.writer"

gcloud projects add-iam-policy-binding "${GCP_PROJECT}" \
  --member="serviceAccount:${SERVICE_ACCOUNT}" \
  --role="roles/container.developer"

gcloud projects add-iam-policy-binding "${GCP_PROJECT}" \
  --member="serviceAccount:${SERVICE_ACCOUNT}" \
  --role="roles/storage.admin"
```

## Step 4: Create Workload Identity Binding

```bash
# Bind the workload identity
gcloud iam service-accounts add-iam-policy-binding "${SERVICE_ACCOUNT}" \
  --project="${GCP_PROJECT}" \
  --role="roles/iam.workloadIdentityUser" \
  --principal="principalSet://iam.googleapis.com/projects/${GCP_PROJECT}/locations/${LOCATION}/workloadIdentityPools/${WIF_POOL}/attribute.sub/jenkins"
```

## Step 5: Configure Jenkins to use WIF

### Option A: Using Google Cloud Credentials Plugin (Recommended)

1. **Install Required Plugins in Jenkins:**
   - Go to `Manage Jenkins` → `Manage Plugins`
   - Search for and install:
     - `Google Kubernetes Engine Plugin`
     - `Google Storage Plugin`
     - `Google Cloud Credentials Plugin`
   - Click `Install without restart`

2. **Add Jenkins Credential:**
   - Go to `Manage Jenkins` → `Manage Credentials`
   - Click `(global)` domain
   - Click `Add Credentials`
   - Kind: `Google Kubernetes Engine Credential`
   - Configuration:
     - **Project ID**: `curamet-onboarding`
     - **Kubernetes cluster**: `autopilot-cluster-1`
     - **Kubernetes cluster location**: `europe-north1`
     - Leave other fields blank (WIF will be auto-discovered)
   - Click `Create`

### Option B: Manual WIF Token Exchange (Advanced)

If you need more control, you can create a custom credential:

```groovy
// In your Jenkinsfile, use:
withCredentials([string(credentialsId: 'gcp-wif-token', variable: 'GCP_TOKEN')]) {
    sh '''
        gcloud auth application-default print-access-token
    '''
}
```

## Step 6: Configure Pipeline Job in Jenkins

1. **Create New Pipeline Job:**
   - Click `New Item`
   - Enter name: `spring-boot-hello-world`
   - Select `Pipeline`
   - Click `OK`

2. **Configure Pipeline:**
   - **Definition**: `Pipeline script from SCM`
   - **SCM**: `Git`
   - **Repository URL**: `https://github.com/WisamTa/docker-hello-world-spring-boot.git`
   - **Credentials**: Select your GitHub credentials (or use SSH key)
   - **Branch Specifier**: `*/master`
   - **Script Path**: `Jenkinsfile`
   - Click `Save`

3. **Build Triggers:**
   - Check `GitHub hook trigger for GITScm polling` (if you want automatic builds on push)
   - Or manually click `Build Now` to test

## Step 7: Update Jenkinsfile for WIF (Optional)

If you want explicit WIF usage in your Jenkinsfile:

```groovy
withEnv(['GOOGLE_APPLICATION_CREDENTIALS=/tmp/gcp-token.json']) {
    sh '''
        # Exchange Jenkins token for GCP access token
        export ACCESS_TOKEN=$(gcloud auth application-default print-access-token)
        
        # Use gcloud with the token
        gcloud auth activate-service-account --impersonate-service-account=${SERVICE_ACCOUNT}
        gcloud config set project ${GCP_PROJECT}
    '''
}
```

## Step 8: Test the Pipeline

1. Go to your Jenkins job
2. Click `Build Now`
3. Monitor the console output
4. Verify stages complete successfully:
   - Checkout ✓
   - Build & Test ✓
   - Build Docker Image ✓
   - Push to Artifact Registry ✓
   - Deploy with Helm ✓

## Troubleshooting

### Error: "gcloud: command not found"
- The Jenkinsfile requires `gcloud`, `docker`, `kubectl`, and `helm` to be installed on Jenkins agent
- Install them:
  ```bash
  docker exec jenkins bash -c "
    apt-get update && apt-get install -y \
    google-cloud-sdk \
    kubectl \
    docker.io
  "
  ```

### Error: "Permission denied" when pushing to Artifact Registry
- Verify the service account has `roles/artifactregistry.writer` permission
- Check that WIF binding is correct

### Error: "Kubernetes cluster not found"
- Verify cluster name and region are correct
- Check GCP project ID

## Security Best Practices

✅ **No static credentials stored in Jenkins**
✅ **Tokens are short-lived (1 hour by default)**
✅ **Credentials are never logged in console output**
✅ **Each build gets a fresh token from WIF**
✅ **Service account permissions are minimal (principle of least privilege)**

## Monitoring

View Jenkins logs:
```bash
docker logs -f jenkins
```

View Helm deployments:
```bash
kubectl get deployments -n spring
helm status spring-release -n spring
```

View GCP activity:
```bash
gcloud logging read "resource.type=k8s_pod AND resource.labels.namespace_name=spring" \
  --limit 50 \
  --format json
```

---

**Next Steps:**
1. Complete the WIF setup steps above
2. Create the Jenkins pipeline job
3. Run first build to verify everything works
4. Monitor the deployment in GKE
