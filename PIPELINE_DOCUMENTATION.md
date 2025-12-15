# Spring Boot CI/CD Pipeline Documentation

## Overview

This GitHub Actions pipeline provides a complete CI/CD solution for the Spring Boot Hello World application, including building, testing, Docker image creation, and Kubernetes deployment.

## Pipeline Architecture

```
Code Push to main/develop
         ↓
┌────────────────────────────────────────┐
│  build-and-test (Parallel Jobs)        │
│  - Maven build                         │
│  - Unit tests                          │
│  - Artifact upload                     │
├────────────────────────────────────────┤
│  code-quality (Parallel Jobs)          │
│  - SonarQube scan (optional)           │
├────────────────────────────────────────┤
│  build-and-push-image (Sequential)     │
│  - Depends on: build-and-test ✓        │
│  - Docker build                        │
│  - Push to GHCR                        │
├────────────────────────────────────────┤
│  deploy-to-kubernetes (Sequential)     │
│  - Depends on: build-and-push-image ✓  │
│  - Only on main branch                 │
│  - Apply K8s manifests                 │
│  - Rollout verification                │
└────────────────────────────────────────┘
         ↓
    Deployment Complete
```

## Workflow Files

Location: `.github/workflows/ci-cd.yml`

## Trigger Conditions

The pipeline runs automatically on:

1. **Push to main/develop branches**
   - When code changes in: `src/`, `pom.xml`, `Dockerfile`, or workflow file
   - Runs full pipeline (build → test → Docker → deploy)

2. **Pull Requests to main**
   - Only runs build and test stages
   - Docker image push skipped
   - Kubernetes deployment skipped

## Pipeline Stages

### Stage 1: Build & Test

**Job**: `build-and-test`
**Runs on**: Ubuntu Latest
**Duration**: ~2-3 minutes

#### Steps:

1. **Checkout Code**
   - Fetches the repository with full history

2. **Setup Java 17**
   - Installs Eclipse Temurin JDK 17
   - Caches Maven dependencies for faster builds

3. **Build with Maven**
   ```bash
   mvn clean package -DskipTests
   ```
   - Compiles Java code
   - Packages as JAR file
   - Location: `target/*.jar`

4. **Run Tests**
   ```bash
   mvn test
   ```
   - Executes unit tests
   - Continues even if tests fail (continues-on-error)

5. **Upload Artifacts**
   - Stores JAR file for 5 days
   - Available in Actions tab
   - Name: `spring-boot-jar`

### Stage 2: Code Quality

**Job**: `code-quality`
**Runs on**: Ubuntu Latest
**Duration**: ~1-2 minutes

#### Steps:

1. **Checkout Code**

2. **Setup Java 17**

3. **SonarQube Scan** (Optional)
   - Requires: `SONARQUBE_HOST` and `SONARQUBE_TOKEN` secrets
   - Analyzes code quality
   - Generates reports
   - Continues even if scan fails

### Stage 3: Build & Push Docker Image

**Job**: `build-and-push-image`
**Runs on**: Ubuntu Latest
**Duration**: ~3-5 minutes
**Conditions**:
- Only on push (not PR)
- Only to main or develop branches
- Only if build-and-test succeeded

#### Steps:

1. **Checkout Code**

2. **Setup Docker Buildx**
   - Enables advanced Docker features
   - Multi-platform builds
   - Build caching

3. **Login to Container Registry**
   - Logs in to GitHub Container Registry (GHCR)
   - Uses GitHub token for authentication

4. **Extract Metadata**
   - Generates image tags:
     - Branch name (e.g., `main`)
     - Git SHA (commit hash)
     - Semantic version tags

5. **Build and Push Image**
   - Builds Docker image from Dockerfile
   - Pushes to `ghcr.io/WisamTa/docker-hello-world-spring-boot`
   - Caches layers for faster builds
   - Image size: ~200MB (JDK 17 + Spring Boot app)

### Stage 4: Deploy to Kubernetes

**Job**: `deploy-to-kubernetes`
**Runs on**: Ubuntu Latest
**Duration**: ~1-2 minutes
**Conditions**:
- Only on main branch push
- Only if build-and-push-image succeeded

#### Steps:

1. **Checkout Code**

2. **Setup kubectl**
   - Installs latest kubectl version

3. **Configure Kubeconfig**
   - Sets up Kubernetes cluster access
   - Uses `KUBE_CONFIG` secret (base64 encoded)
   - **Required**: You must add this secret with your cluster config

4. **Deploy to Kubernetes**
   ```bash
   kubectl apply -f k8s-deployment.yaml
   kubectl rollout status deployment/spring-test-deployment -n spring
   ```
   - Applies Kubernetes manifests
   - Waits for rollout (up to 5 minutes)

5. **Verify Deployment**
   - Displays deployment status
   - Lists pods and services
   - Confirms successful rollout

## GitHub Secrets Required

Add these secrets to your GitHub repository: Settings → Secrets and variables → Actions

### Required Secrets:

1. **GITHUB_TOKEN** (Built-in)
   - Automatically available
   - Used for Docker registry authentication

### Optional Secrets:

1. **SONARQUBE_HOST**
   - Example: `https://sonarqube.example.com`
   - Leave empty to skip code quality scan

2. **SONARQUBE_TOKEN**
   - Generated from SonarQube instance
   - Leave empty to skip code quality scan

### For Kubernetes Deployment:

1. **KUBE_CONFIG** (Required for K8s deployment)
   - Your cluster kubeconfig file, base64 encoded
   - Generate with:
     ```bash
     cat ~/.kube/config | base64 -w 0
     ```
   - Add as secret: `KUBE_CONFIG`

## Project Structure

```
docker-hello-world-spring-boot/
├── .github/
│   └── workflows/
│       └── ci-cd.yml           ← Pipeline definition
├── src/
│   ├── main/
│   │   ├── java/              ← Java source code
│   │   └── resources/         ← Application properties
│   └── test/
│       └── java/              ← Unit tests
├── pom.xml                    ← Maven configuration
├── Dockerfile                 ← Docker image definition
├── k8s-deployment.yaml        ← Kubernetes manifest
├── Jenkinsfile               ← Jenkins pipeline (alternative)
├── docker-compose.yml        ← Local development
└── README.md
```

## Docker Image Details

**Base Images**:
- Build stage: `maven:3.9-eclipse-temurin-17`
- Runtime stage: `eclipse-temurin:17-jdk`

**Image Registry**: GitHub Container Registry (GHCR)
**Full Image URL**: `ghcr.io/WisamTa/docker-hello-world-spring-boot:main`

**Build Process**:
1. Multi-stage build (reduces final image size)
2. First stage: Maven builds the JAR
3. Second stage: JDK runs the application
4. Exposed port: 8080

## Kubernetes Deployment

**Manifest**: `k8s-deployment.yaml`

**Deployment Details**:
- Namespace: `spring`
- Service: `spring-test-service`
- Port: 8080
- Replicas: Defined in manifest

**Commands**:
```bash
# View deployment status
kubectl get deployment -n spring

# View pods
kubectl get pods -n spring

# View service
kubectl get svc -n spring

# Port forward for local access
kubectl port-forward svc/spring-test-service 8080:8080 -n spring
```

## Local Development

### Build Locally

```bash
cd docker-hello-world-spring-boot

# Maven build
mvn clean package

# Run tests
mvn test

# Run application
java -jar target/hello-world-0.1.0.jar
```

### Docker Build Locally

```bash
cd docker-hello-world-spring-boot

# Build image
docker build -t spring-hello:latest .

# Run container
docker run -p 8080:8080 spring-hello:latest

# Access application
curl http://localhost:8080
```

### Docker Compose

```bash
# Start services
docker-compose up -d

# Stop services
docker-compose down

# View logs
docker-compose logs -f
```

## Troubleshooting

### Build Fails: "Maven not found"

**Solution**: Ensure Java setup step completes before Maven commands

### Docker Push Fails: "Permission Denied"

**Solution**: Verify GITHUB_TOKEN has `packages:write` permission in workflow

### Kubernetes Deployment Fails: "Cannot connect to cluster"

**Solution**: 
1. Verify `KUBE_CONFIG` secret is set correctly
2. Ensure config file is base64 encoded: `cat config | base64 -w 0`
3. Check cluster connectivity: `kubectl cluster-info`

### Tests Fail but Pipeline Continues

**Current behavior**: Tests marked with `continue-on-error: true`

**To fail on test failure**:
```yaml
- name: Run Tests
  run: mvn test
  # Remove continue-on-error
```

### Image Too Large

**Current size**: ~200MB (JDK 17 base)

**To reduce**:
1. Use lighter base image: `alpine:latest` + custom JDK
2. Multi-stage build (already implemented)
3. Use jlink to create custom JDK runtime

## Performance Tips

1. **Enable Docker Cache**
   - Already configured in workflow
   - Significantly speeds up builds

2. **Cache Maven Dependencies**
   - Already configured with `cache: maven`
   - First build slower, subsequent faster

3. **Skip Tests in Draft PRs**
   ```yaml
   if: "!contains(github.head_ref, 'draft')"
   ```

4. **Parallel Jobs**
   - build-and-test and code-quality run in parallel
   - Saves ~2-3 minutes per run

## Monitoring & Logs

### View Workflow Logs

1. Go to GitHub repository
2. Click **Actions** tab
3. Select recent workflow run
4. Click job name to view logs
5. Expand individual steps for details

### Download Artifacts

1. Go to workflow run summary
2. Scroll to **Artifacts** section
3. Click download button
4. JAR file available for 5 days

## Best Practices

✅ **Do**:
- Write unit tests for all features
- Keep Dockerfile optimized
- Use semantic versioning
- Review K8s manifests before deployment
- Monitor deployment health

❌ **Don't**:
- Commit secrets to repository
- Use `latest` tag in production
- Deploy without testing
- Ignore failed tests
- Skip code quality checks

## Next Steps

1. **Setup Secrets**:
   - Add `KUBE_CONFIG` secret for K8s deployment
   - Add `SONARQUBE_*` secrets for code analysis (optional)

2. **Configure K8s Manifest**:
   - Update `k8s-deployment.yaml` with your settings
   - Verify namespace exists: `kubectl create ns spring`

3. **Test Pipeline**:
   - Make a small change to `src/`
   - Push to develop branch
   - Monitor workflow run
   - Verify Docker image in GHCR
   - Verify K8s deployment

4. **Monitor Production**:
   - Setup monitoring/logging
   - Configure alerts
   - Track deployment metrics

## Support

For issues or questions:
1. Check workflow logs (Actions tab)
2. Review troubleshooting section above
3. Verify all required secrets are set
4. Test locally with `mvn` and `docker`

---

**Last Updated**: December 15, 2025
**Pipeline Version**: 1.0
