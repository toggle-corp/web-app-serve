## Usage Guide

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
```dockerfile
# Builder stage
FROM node:18-bullseye AS dev

# ...other required steps

# ---------------------------------------------------------------------
# Build stage for web app
FROM dev AS web-app-serve-build

# ...other required steps

# Static variables
ENV APP_GRAPHQL_CODEGEN_ENDPOINT=./montandon-etl/schema.graphql

# Placeholder variables for build which needs to be changed when used
ENV APP_TITLE=APP_TITLE_PLACEHOLDER
ENV APP_GRAPHQL_ENDPOINT=APP_API_ENDPOINT_PLACEHOLDER

RUN pnpm generate:type && pnpm build

# ---------------------------------------------------------------------
# Final image with nginx to serve the app
FROM ghcr.io/toggle-corp/web-app-serve:v0.1.1 AS web-app-serve

LABEL maintainer="Me"
LABEL org.opencontainers.image.source="https://github.com/my-org/my-best-dashboard"

# Environment for configuration script
ENV APPLY_CONFIG__APPLY_CONFIG_PATH=/code/apply-config.sh
ENV APPLY_CONFIG__SOURCE_DIRECTORY=/code/build/

COPY --from=web-app-serve-build /code/build "$APPLY_CONFIG__SOURCE_DIRECTORY"
COPY ./web-app-serve/apply-config.sh "$APPLY_CONFIG__APPLY_CONFIG_PATH"
````
> [!IMPORTANT]
> For more config options, see [./src/apply-config.sh](./src/apply-config.sh)

### Configuration script (`apply-config.sh`)

This script replaces placeholders with real values:
```bash
#!/bin/bash -xe

find "$DESTINATION_DIRECTORY" -type f -exec sed -i "s|\<APP_TITLE_PLACEHOLDER\>|$APP_TITLE|g" {} +
find "$DESTINATION_DIRECTORY" -type f -exec sed -i "s|\<APP_API_ENDPOINT_PLACEHOLDER\>|$APP_GRAPHQL_ENDPOINT|g" {} +
```
> [!IMPORTANT]
> `DESTINATION_DIRECTORY` is set by the internal web-app-serve script. see [./src/apply-config.sh](./src/apply-config.sh) search for `apply_config`
>
> Environment variables (`APP_TITLE`, `APP_GRAPHQL_ENDPOINT`) must:
> - match the placeholder names used during build. see Dockerfile
> - be passed to the container at runtime.

### Docker Compose (`web-app-serve/docker-compose.yml`)

```yaml
name: my-org-my-best-dashboard

services:
  web-app-serve:
    build:
      context: ../
      target: web-app-serve
    environment:
      APPLY_CONFIG__ENABLE_DEBUG: true
      APP_TITLE: ${APP_TITLE:-My Dashboard}
      APP_GRAPHQL_ENDPOINT: ${APP_GRAPHQL_ENDPOINT:-http://localhost:8000/graphql/}
    ports:
      - '8001:80'
    develop:
      watch:
        - action: sync+restart
          path: ../web-app-serve/apply-config.sh
          target: /code/apply-config.sh
```
> [!Warning]
> To use develop.watch, enable Docker Compose watch mode: \
> https://docs.docker.com/compose/how-tos/file-watch/

### How to Debug Locally

Run this command to start the app with live config updates:

```bash
docker compose -f web-app-serve/docker-compose.yml up
```
Changes to `web-app-serve/apply-config.sh` will be picked up automatically when docker watch is enabled

### GitHub Actions Workflow (`.github/workflows/publish-web-app-serve.yml`)

> This workflow builds and publishes the Docker image when changes are pushed to specific branches.
```yaml
name: Publish nginx serve image

on:
  workflow_dispatch:
  push:
    branches:
      - develop
      - feature/*

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
