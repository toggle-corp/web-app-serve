# web-app-serve

## Docker Guide

This guide shows how to package a Web app (SPA and Vite) using Docker with a base image that allows configuration to be changed when the Nginx container starts.

We use simple tools like `nginx`, `find`, `sed`, and `diff2html` to help package and debug SPA deployments.

For actual examples, see:

- https://github.com/IFRCGo/go-web-app/
    - https://github.com/IFRCGo/go-web-app/tree/develop/web-app-serve
    - https://github.com/IFRCGo/go-web-app/blob/develop/.github/workflows/publish-web-app-serve.yml
    - https://github.com/IFRCGo/go-web-app/blob/develop/Dockerfile
    - https://github.com/IFRCGo/go-web-app/blob/develop/app/env.ts

### Project Structure

```
├── .github/workflows
│    └── publish-web-app-serve.yml
├── web-app-serve
│    ├── .env
│    ├── .gitignore
│    └── docker-compose.yml
└── Dockerfile
````

### Setting up env variables placeholder using Vite

In this guide, our example app uses these env variables:

- `APP_TITLE`
- `APP_GRAPHQL_ENDPOINT`

> [!IMPORTANT]
> Replace them with the env variables for your own app.

Use `vite-plugin-validate-env` plugin (togglecorp fork)

```json
{
  "devDependencies": {
      "@julr/vite-plugin-validate-env": "git+https://github.com/toggle-corp/vite-plugin-validate-env#97fc110"
  }
}
```

> [!TIP]
> Check the latest version of `vite-plugin-validate-env` at https://github.com/toggle-corp/vite-plugin-validate-env/

Update the `./env.ts` file and define `overrideDefine` config to enable env variable placeholder:

```typescript
import { Schema, defineConfig } from '@julr/vite-plugin-validate-env';

const webAppServeEnabled = process.env.WEB_APP_SERVE_ENABLED?.toLowerCase() === 'true';
if (webAppServeEnabled) {
  console.warn('Building application for WEB_APP_SERVE')
}

export default defineConfig({
  validator: "builtin",
  schema: {
      // NOTE: These are the dynamic env variables
      APP_TITLE: Schema.string(),
      APP_GRAPHQL_ENDPOINT: Schema.string({ format: 'url', protocol: true, tld: false }),
  },
  overrideDefine: (key, value) => {
    // Default:
    if (!webAppServeEnabled) {
      return JSON.stringify(value);
    }
    // Override: Skip defining env variables if web app serve is enabled
    if (value === null || value === undefined) {
      // NOTE: value should always be defined during build
      throw `Value for ${key} should not be null or undefined`;
    }
    const replacement_str = `WEB_APP_SERVE_PLACEHOLDER__${key}`;
    // NOTE: For string values, we need to stringify 'replacement_str'
    // This adds double quotes around the replacement string
    return typeof value === 'string'
      ? JSON.stringify(replacement_str)
      : replacement_str;
  },
});
```

### Setting up Dockerfile

To package a Web app using `web-app-serve`, we'll define a Dockerfile that includes:

1. A build step for your app with env variables placeholder.
2. A final image using `web-app-serve` that updates those placeholders at runtime.

```dockerfile
# Builder stage
FROM node:18-bullseye AS dev

# ... add your build steps here ...

# ---------------------------------------------------------------------
# Build stage for web app
FROM dev AS web-app-serve-build

# ... add your build steps here ...

# NOTE: Dynamic env variables
# These env variables can be dynamicallly defined in web-app-serve container runtime.
# These variables are not included in the build files but the values should still be valid.
# See "schema" field in "./env.ts"
ENV APP_TITLE=My Best Dashboard
ENV APP_GRAPHQL_ENDPOINT=https://my-best-dashboard.com/graphql/

# NOTE: Static env variables:
# These env variables are used during build
ENV APP_GRAPHQL_CODEGEN_ENDPOINT=./backend/schema.graphql

# NOTE: WEB_APP_SERVE_ENABLED=true will skip defining the above dynamic env variables
# See "overrideDefine" field in "./env.ts"
RUN WEB_APP_SERVE_ENABLED=true pnpm build

# ---------------------------------------------------------------------
# Final image using web-app-serve
FROM ghcr.io/toggle-corp/web-app-serve:v0.1.1 AS web-app-serve

LABEL org.opencontainers.image.source="https://github.com/my-org/my-best-dashboard"
LABEL org.opencontainers.image.authors="my-email@company.com"

# Env for apply-config script
ENV APPLY_CONFIG__SOURCE_DIRECTORY=/code/build/

COPY --from=web-app-serve-build /code/build "$APPLY_CONFIG__SOURCE_DIRECTORY"
````

> [!IMPORTANT]
> Make sure all the dynamic environment variables are prefixed with `APP_`

> [!IMPORTANT]
> Make sure all the environment variables are defined (e.g. `APP_TITLE`, `APP_GRAPHQL_ENDPOINT`)\
> These values will be replaced at runtime.

### Setting up Docker Compose for debugging locally (`web-app-serve/docker-compose.yml`)

Create a `docker-compose.yml` file

```yaml
# NOTE: The name should is mandatory and should be unique
name: my-org-my-best-dashboard

services:
  web-app-serve:
    build:
      context: ../
      target: web-app-serve
    environment:
      # web-app-serve config
      APPLY_CONFIG__ENABLE_DEBUG: true
    # NOTE: See "Dockerfile" to get dynamic env variables for .env file
    env_file: .env
    ports:
      - '8050:80'
```

Create `.env` file

```bash
APP_TITLE=My Good Dashboard
APP_GRAPHQL_ENDPOINT=https://my-good-dashboard.com/graphql/
```

> [!WARNING]
> Replace them with the env variables for your own app.

Make sure `.env` is ignored by git

```bash
echo ".env" >> .gitignore
```

Run

```bash
docker compose -f web-app-serve/docker-compose.yml up --build
```

> [!TIP]
> Re-run the command if you make any change

### Setting up GitHub Actions Workflow (`.github/workflows/publish-web-app-serve.yml`)

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
> If your application uses submodules, make sure to add `with.submodules: true` to the `actions/checkout` step.

> [!IMPORTANT]
> To see what this action does internally, check: [.github/actions/publish-web-app-serve/action.yml](.github/actions/publish-web-app-serve/action.yml)

> [!TIP]
> To run this workflow on a Pull Request, temporarily add your branch to the `on.push.branches` list.

> [!TIP]
> To avoid creating redundant images, remove `on.push` from the workflow and use `workflow_dispatch` to run it manually.\
> If you have [gh](https://cli.github.com/) setup locally, you can use this command to trigger it from your command line
> ```bash
> gh workflow run .github/workflows/publish-web-app-serve.yml --ref $(git rev-parse --abbrev-ref HEAD)`
> ```
> This will only work after `.github/workflows/publish-web-app-serve.yml` is added to the repo default branch.

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
