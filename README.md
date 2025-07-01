# web-app-serve

## Related repositories
- https://github.com/toggle-corp/web-app-serve-helm
- https://github.com/toggle-corp/web-app-serve-action

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
- `APP_ANALYTIC_SRC`

> [!IMPORTANT]
> Replace them with the env variables for your own app.

Add `vite-plugin-validate-env` plugin as dependency (togglecorp fork)

```diff
  {
      "devDependencies": {
+         "@julr/vite-plugin-validate-env": "git+https://github.com/toggle-corp/vite-plugin-validate-env#v2.2.0-tc.1",
      }
  }
```

> [!TIP]
> Check the latest version of `vite-plugin-validate-env` at https://github.com/toggle-corp/vite-plugin-validate-env/releases

Update the `./env.ts` file and define `overrideDefine` config to enable env variable placeholder:

```diff
- import { Schema, defineConfig } from '@julr/vite-plugin-validate-env';
+ import {
+     defineConfig,
+     overrideDefineForWebAppServe,
+     Schema,
+ } from '@julr/vite-plugin-validate-env';
+
+ const webAppServeEnabled = process.env.WEB_APP_SERVE_ENABLED?.toLowerCase() === 'true';
+ if (webAppServeEnabled) {
+     // eslint-disable-next-line no-console
+     console.warn('Building application for web-app-serve');
+ }
+ const overrideDefine = webAppServeEnabled
+     ? overrideDefineForWebAppServe
+     : undefined;

  export default defineConfig({
+     overrideDefine,
      validator: 'builtin',
      schema: {
          // NOTE: These are the dynamic env variables
          APP_TITLE: Schema.string(),
          APP_GRAPHQL_ENDPOINT: Schema.string({ format: 'url', protocol: true, tld: false }),
      },
  });
```
> [!TIP]
> To learn more about what `overrideDefineForWebAppServe` does,\
> visit: https://github.com/toggle-corp/vite-plugin-validate-env/blob/main/src/index.ts \
> Look for `overrideDefineForWebAppServe` in the file.


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
# These env variables can be dynamically defined in web-app-serve container runtime.
# These variables are not included in the build files but the values should still be valid.
# See "schema" field in "./env.ts"
ENV APP_TITLE=My Best Dashboard
ENV APP_GRAPHQL_ENDPOINT=https://my-best-dashboard.com/graphql/

# NOTE: These are set directly in `vite.config.ts`
# We're using raw web-app-serve placeholder values here to treat them as dynamic values
ENV APP_ANALYTIC_SRC=WEB_APP_SERVE_PLACEHOLDER__APP_ANALYTIC_SRC

# NOTE: Static env variables:
# These env variables are used during build
ENV APP_GRAPHQL_CODEGEN_ENDPOINT=./backend/schema.graphql

# NOTE: WEB_APP_SERVE_ENABLED=true will skip defining the above dynamic env variables
# See "overrideDefine" field in "./env.ts"
RUN WEB_APP_SERVE_ENABLED=true pnpm build

# ---------------------------------------------------------------------
# Final image using web-app-serve
FROM ghcr.io/toggle-corp/web-app-serve:v0.1.2 AS web-app-serve

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

### Setting up Docker Compose for debugging locally

Create a `web-app-serve/docker-compose.yml` file

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

Create `web-app-serve/.env` file

```ini
APP_TITLE=My Good Dashboard
APP_GRAPHQL_ENDPOINT=https://my-good-dashboard.com/graphql/
APP_ANALYTIC_SRC=https://my-good-analytic.com/script.js
```

> [!WARNING]
> Replace them with the env variables for your own app.

Make sure `web-app-serve/.env` is ignored by git

```bash
echo ".env" >> web-app-serve/.gitignore
```

Run

```bash
docker compose -f web-app-serve/docker-compose.yml up --build
```

> [!TIP]
> Re-run the command if you make any change

### Setting up GitHub Actions Workflow

Create `.github/workflows/publish-web-app-serve.yml` file\
This workflow builds and pushes your Docker image to the GitHub container registry.

```yaml
name: Publish web app serve

on:
  workflow_dispatch:
  push:
    branches:
      - develop

permissions:
  packages: write

jobs:
  publish_image:
    name: Publish Docker Image
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          submodules: true

      - name: Publish web-app-serve
        uses: toggle-corp/web-app-serve-action@v0.1.1
        with:
          github_token: ${{ secrets.GITHUB_TOKEN }}
```

> [!IMPORTANT]
> If your app doesn't use submodules, remove `submodules: true` from the `actions/checkout` step.

> [!IMPORTANT]
> To see what this action does internally, check: [.github/actions/publish-web-app-serve/action.yml](.github/actions/publish-web-app-serve/action.yml)

> [!TIP]
> To run this workflow on a Pull Request, temporarily add your branch to the `on.push.branches` list.

> [!TIP]
> To avoid redundant image builds, this workflow only runs on the `develop` (default) branch or when triggered manually.
> If you have [GitHub CLI (gh)](https://cli.github.com/) set up, you can run this from your terminal:
>
> ```bash
> gh workflow run .github/workflows/publish-web-app-serve.yml --ref $(git rev-parse --abbrev-ref HEAD)
> ```
>
> This will only work after the workflow file exists on the `develop` (default) branch.


## K8s Guide

See [./docs/kubernetes.md](./docs/kubernetes.md)
