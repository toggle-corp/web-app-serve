## Docker Guide

This guide shows how to package a frontend (React) app using Docker with a base image that allows configuration to be changed when the Nginx container starts.

We use simple tools like `nginx`, `find`, `sed`, and `diff2html` to help package and debug SPA (Single Page Application) deployments.

For real examples, see:  
- https://github.com/IFRCGo/go-api

### Project Structure

```

├── .github/workflows
│    └── publish-web-app-serve.yml
├── web-app-serve
│    ├── apply-config.sh
│    └── docker-compose.yml
└── Dockerfile

````

### Dockerfile Overview

To package a React app using `web-app-serve`, we'll define a Dockerfile that includes:

1. A build step for our app with placeholder values.
2. A final image using `web-app-serve` that updates those placeholders at runtime.

```dockerfile
# Builder stage
FROM node:18-bullseye AS dev

# ... add your build steps here

# ---------------------------------------------------------------------
# Build stage for web app
FROM dev AS web-app-serve-build

# ... add your build steps here

# Static value (used in build process)
ENV APP_GRAPHQL_CODEGEN_ENDPOINT=./montandon-etl/schema.graphql

# Placeholder values (to be replaced later)
ENV APP_TITLE=APP_TITLE_PLACEHOLDER
ENV APP_GRAPHQL_ENDPOINT=APP_API_ENDPOINT_PLACEHOLDER

RUN pnpm build

# ---------------------------------------------------------------------
# Final image using web-app-serve
FROM ghcr.io/toggle-corp/web-app-serve:v0.1.1 AS web-app-serve

LABEL maintainer="Me"
LABEL org.opencontainers.image.source="https://github.com/my-org/my-best-dashboard"

# Environment for apply-config script
ENV APPLY_CONFIG__APPLY_CONFIG_PATH=/code/apply-config.sh
ENV APPLY_CONFIG__SOURCE_DIRECTORY=/code/build/

COPY --from=web-app-serve-build /code/build "$APPLY_CONFIG__SOURCE_DIRECTORY"
COPY ./web-app-serve/apply-config.sh "$APPLY_CONFIG__APPLY_CONFIG_PATH"
````

> [!TIP]
> For more config options, check: [./src/apply-config.sh](./src/apply-config.sh)

> [!IMPORTANT]
> Everything above `# Final image with web-app-serve to serve the app` is placeholder code.
> Replace it with your actual build steps.

> [!NOTE]
> Make sure `APP_TITLE` and `APP_GRAPHQL_ENDPOINT` match what your app needs.
> These values will be replaced at runtime.

---

### Configuration Script (`apply-config.sh`)

This script replaces placeholder values with real ones during container runtime.

Example:

```bash
#!/bin/bash -xe

find "$DESTINATION_DIRECTORY" -type f -exec sed -i "s|\<APP_TITLE_PLACEHOLDER\>|$APP_TITLE|g" {} +
find "$DESTINATION_DIRECTORY" -type f -exec sed -i "s|\<APP_API_ENDPOINT_PLACEHOLDER\>|$APP_GRAPHQL_ENDPOINT|g" {} +
```

> [!IMPORTANT]
> `DESTINATION_DIRECTORY` is set internally by `web-app-serve`.
> Environment variables like `APP_TITLE` and `APP_GRAPHQL_ENDPOINT` must:
>
> - Match placeholders used in your app build
> - Be passed into the container at runtime

> [!IMPORTANT]
> Make the script executable:
> `chmod +x web-app-serve/apply-config.sh`


### Docker Compose (`web-app-serve/docker-compose.yml`)

Use Docker Compose for local testing with live configuration updates.

```yaml
name: my-org-my-best-dashboard

services:
  web-app-serve:
    build:
      context: ../
      target: web-app-serve
    environment:
      # web-app-serve config
      APPLY_CONFIG__ENABLE_DEBUG: true
      # Placeholder replacement variables
      APP_TITLE: ${APP_TITLE:-My Dashboard}
      APP_GRAPHQL_ENDPOINT: ${APP_GRAPHQL_ENDPOINT:-http://localhost:8000/graphql/}
    ports:
      - '8001:80'
    develop:
      watch:
        - action: sync+restart
          path: ./apply-config.sh
          target: /code/apply-config.sh
```

> [!IMPORTANT]
> To use `services.develop.watch`, enable Docker Compose watch mode: https://docs.docker.com/compose/how-tos/file-watch/

To run:

```bash
# After making changes
docker compose -f web-app-serve/docker-compose.yml build

docker compose -f web-app-serve/docker-compose.yml up
```

When watch mode is enabled, updates to `apply-config.sh` are applied automatically.


### GitHub Actions Workflow (`.github/workflows/publish-web-app-serve.yml`)

This workflow builds and pushes your Docker image to the GitHub container registry.

```yaml
name: Publish web app serve

on:
  workflow_dispatch:
  push:
    branches:
      - develop
      - project/*

permissions:
  packages: write

jobs:
  publish_image:
    name: Publish Docker Image
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Publish web-app-serve
        uses: toggle-corp/web-app-serve/.github/actions/publish-web-app-serve@v0.1.1
        with:
          github_token: ${{ secrets.GITHUB_TOKEN }}
```
> [!IMPORTANT]
> To see what this action does internally, check: [.github/actions/publish-web-app-serve/action.yml](.github/actions/publish-web-app-serve/action.yml)

## K8s Guide

### Using Helm (Direct)

**Download the Helm chart**

```bash
helm pull oci://ghcr.io/toggle-corp/web-app-serve-helm
```

**Create a config file**

Save as `my-values.yaml`:

```yaml
fullnameOverride: my-web-app
ingress:
  ingressClassName: nginx
  hostname: my-dashboard.togglecorp.com
image:
  name: ghcr.io/toggle-corp/my-dashboard
  tag: feat-web-app-serve.cXXXXXXX
resources:
  requests:
    cpu: "0.1"
    memory: "100Mi"
  limits:
    memory: "300Mi"  # For debug mode (biome needs more RAM at initial start)
env:
  APPLY_CONFIG__ENABLE_DEBUG: true
  APP_TITLE: "My Dashboard"
  APP_GRAPHQL_ENDPOINT: https://my-dashboard-api.togglecorp.com/graphql/
```

**Deploy to Kubernetes**

```bash
# Create namespace
kubectl create namespace test-my-dashboard

# Install (or upgrade) the Helm release
helm upgrade --install \
  -n test-my-dashboard \
  my-dashboard \
  oci://ghcr.io/toggle-corp/web-app-serve-helm \
  --values ./my-values.yaml
```

---

### Using Helm with ArgoCD

Example ArgoCD `Application` manifest:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-web-app
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  destination:
    name: in-cluster
    namespace: my-web-app
  source:
    chart: web-app-serve-helm
    repoURL: ghcr.io/toggle-corp
    targetRevision: 0.1.1
    helm:
      valuesObject:
        fullnameOverride: my-web-app
        ingress:
          ingressClassName: nginx
          hostname: https://my-dashboard.togglecorp.com
        image:
          name: ghcr.io/toggle-corp/my-dashboard
          tag: feat-web-app-serve.cXXXXXXX
        resources:
          requests:
            cpu: "0.1"
            memory: "100Mi"
        env:
          # web-app-serve config
          APPLY_CONFIG__ENABLE_DEBUG: true
          # Placeholder replacement variables
          APP_TITLE: "My Dashboard"
          APP_GRAPHQL_ENDPOINT: https://my-dashboard-api.togglecorp.com/graphql/
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    managedNamespaceMetadata:
      labels:
        argocd.argoproj.io/instance: my-web-app
      annotations:
        argocd.argoproj.io/tracking-id: >-
          my-web-app:apps/Namespace:my-web-app/my-web-app
    syncOptions:
      - CreateNamespace=true
```
