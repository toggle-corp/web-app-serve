# K8s Guide

In this guide, our example app uses these env variables:

- `APP_TITLE`
- `APP_GRAPHQL_ENDPOINT`
- `APP_ANALYTIC_SRC`

> [!IMPORTANT]
> Replace them with the env variables for your own app.

## Using Helm (Direct)

Deploy your app's **wrapper chart** (`my-web-app-helm`) that CI publishes — see
[Publish via CI (wrapper chart)](#publish-via-ci-wrapper-chart) below. It bundles
the `web-app-serve-helm` base chart as a dependency (aliased `app`), so all
overrides live under `app:`.

**Download the Helm chart**

```bash
# Use the CI-stamped version (the helm_target_revision output).
helm pull oci://ghcr.io/toggle-corp/my-web-app-helm --version 0.0.0-develop.cabc1234
```

**Create a config file**

Save as `my-values.yaml` (everything nests under the `app` alias):

```yaml
app:
  fullnameOverride: my-web-app
  ingress:
    ingressClassName: nginx
    hostname: my-dashboard.togglecorp.com
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
  # image.{name,tag} are already baked into the published chart by CI.
  # Uncomment to pin a different build:
  # image:
  #   name: ghcr.io/toggle-corp/my-dashboard
  #   tag: feat-web-app-serve.cXXXXXXX
```

**Deploy to Kubernetes**

```bash
# Create namespace
kubectl create namespace test-my-dashboard

# Install (or upgrade) the Helm release
helm upgrade --install \
  -n test-my-dashboard \
  my-dashboard \
  oci://ghcr.io/toggle-corp/my-web-app-helm \
  --version 0.0.0-develop.cabc1234 \
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
    # The app's CI-published wrapper chart (name ends in -helm; -dev-helm for slash branches).
    chart: my-web-app-helm
    repoURL: ghcr.io/toggle-corp
    # CI-stamped wrapper version (the helm_target_revision output). Pin explicitly.
    targetRevision: 0.0.0-develop.cabc1234
    helm:
      valuesObject:
        # Everything nests under the `app` alias (the web-app-serve-helm subchart).
        app:
          fullnameOverride: my-web-app
          ingress:
            ingressClassName: nginx
            hostname: my-dashboard.togglecorp.com
          resources:
            requests:
              cpu: "0.1"
              memory: "100Mi"
          # image.{name,tag} are already baked into the published chart by CI.
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

---

## Publish via CI (wrapper chart)

Instead of hand-maintaining `values.yaml` with the image tag on every deploy,
you can ship a thin **wrapper chart** in your app repo and let CI
(`toggle-corp/web-app-serve-action`) publish a fully-resolved chart to GHCR on
every push. The wrapper depends on the published `web-app-serve-helm` chart
(aliased as `app`), so all overrides live under `app:` and reach the subchart.

### Wrapper chart layout

Keep the wrapper under `web-app-serve/helm/` in your app repo:

```
web-app-serve/
└── helm/
    ├── Chart.yaml     # name ends in `-helm`; version 0.0.0-SET-BY-CICD; depends on web-app-serve-helm (alias: app)
    └── values.yaml    # minimal: app.image.{name,tag} placeholders + app.ingress.annotations: {}
```

`Chart.yaml`:

```yaml
apiVersion: v2
name: my-web-app-helm
description: "Wrapper Helm chart for my-web-app, depends on web-app-serve-helm"
type: application
version: 0.0.0-SET-BY-CICD
dependencies:
  - name: web-app-serve-helm
    version: 0.1.1
    repository: oci://ghcr.io/toggle-corp
    alias: app
```

`values.yaml`:

```yaml
app:
  fullnameOverride: my-web-app
  image:
    name: SET-BY-CICD-IMAGE
    tag: SET-BY-CICD-TAG
  ingress:
    annotations: {}
```

> [!NOTE]
> `values.yaml` intentionally omits `ingress.hostname` and
> `ingress.ingressClassName` — supply them at deploy time under the `app.*`
> alias (see the "Using Helm with ArgoCD" example above). CI's smoke-render
> passes them via `--set` only to validate.

### What CI does

The `helm_publish` path in `toggle-corp/web-app-serve-action`:

1. `helm dependency update` (the base chart is public, no login needed).
2. `helm lint` + `helm template` smoke render.
3. `sed` the `SET-BY-CICD-IMAGE` / `SET-BY-CICD-TAG` placeholders in
   `values.yaml` with the just-built image name and tag.
4. Writes provenance annotations (table below) into `.app.ingress.annotations`.
5. Rewrites the `SET-BY-CICD` chart version (and renames `*-helm` →
   `*-dev-helm` for slash branches).
6. `helm package` + `helm push` to `oci://ghcr.io/<owner>`.

Wire it up with a workflow like `.github/workflows/helm-publish.yaml`:

```yaml
name: Publish Helm

on:
  workflow_call:
  push:

jobs:
  helm-publish:
    name: Publish Helm
    runs-on: ubuntu-latest
    permissions:
      packages: write        # push chart to GHCR
      pull-requests: read    # resolve PR from commit for provenance
    steps:
      - uses: actions/checkout@v4
      - uses: toggle-corp/web-app-serve-action@main  # TODO: pin to a release
        with:
          github_token: ${{ secrets.GITHUB_TOKEN }}
          helm_publish: true
```

### Provenance annotations

CI writes these keys (prefix `web-app-serve.togglecorp.com/`) into
`.app.ingress.annotations`, so they surface as ingress annotations on the
deployed resource. `pr-*` keys are omitted when the commit has no associated PR.

The authoritative definition of this set (types, formats, which keys are
optional) is the versioned JSON Schema in the action repo —
[`schema/annotations-v1.json`](https://github.com/toggle-corp/web-app-serve-action/blob/main/schema/annotations-v1.json);
the `schema-version` annotation pins which schema version applies. The table
below is a summary.

| # | key | source |
|---|---|---|
| 1 | schema-version | literal `"1"` in action |
| 2 | repo-url | `${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}` |
| 3 | ref | `github.ref_name` |
| 4 | ref-type | `github.ref_type` (branch\|tag) |
| 5 | commit | `github.sha` |
| 6 | commit-message | `git log -1 --pretty=%s` |
| 7 | datetime | `date -u +%Y-%m-%dT%H:%M:%SZ` |
| 8 | image-label | image tag (`develop.c3f9c2ab`) |
| 9 | image-url | `ghcr.io/<owner>/<repo>:<tag>` |
| 10 | actor | `github.actor` |
| 11 | actor-image-url | `https://github.com/<actor>.png` |
| 12 | repo-owner-image-url | `https://github.com/<owner>.png` |
| 13 | ci-run-url | `${SERVER_URL}/${REPOSITORY}/actions/runs/${RUN_ID}` |
| 14 | pr-number | `gh api` from commit (omit if no PR) |
| 15 | pr-author | `gh api` from commit (omit if no PR) |
| 16 | pr-author-image-url | `https://github.com/<pr-author>.png` (omit if no PR) |
