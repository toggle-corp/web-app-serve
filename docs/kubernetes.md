# K8s Guide

In this guide, our example app uses these env variables:

- `APP_TITLE`
- `APP_GRAPHQL_ENDPOINT`
- `APP_ANALYTIC_SRC`

> [!IMPORTANT]
> Replace them with the env variables for your own app.

## Using Helm (Direct)

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
  APP_ANALYTIC_SRC: https://my-good-analytic.com/script.js
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

## Using Helm with ArgoCD

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
          APP_ANALYTIC_SRC: https://my-good-analytic.com/script.js
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
