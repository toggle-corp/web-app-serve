## Usages

Directory structure
```
├── .github/workflows
│    └── publish-web-app-serve.yml
├── web-app-serve
│    ├── apply-config.sh
│    └── docker-compose.yml
└── Dockerfile
```

**Dockerfile**
```dockerfile
# -------------------------- Builder -----------------------
FROM node:18-bullseye AS dev

# ....

# -------------------------- Nginx - Builder -----------------------
FROM dev AS web-serve-build

# ....

# Build variables
ENV APP_GRAPHQL_CODEGEN_ENDPOINT=./montandon-etl/schema.graphql

## Build placeholder variables
ENV APP_TITLE=APP_TITLE_PLACEHOLDER
ENV APP_GRAPHQL_ENDPOINT=APP_API_ENDPOINT_PLACEHOLDER

RUN pnpm generate:type && pnpm build

# ---------------------------Nginx - Serve----------------------------------
FROM ghcr.io/toggle-corp/web-app-serve:v0.1.1 AS web-app-serve

LABEL maintainer="Me"
LABEL org.opencontainers.image.source="https://github.com/my-org/my-best-dashboard"

# NOTE: Used by apply-config.sh
ENV APPLY_CONFIG__APPLY_CONFIG_PATH=/code/apply-config.sh
ENV APPLY_CONFIG__SOURCE_DIRECTORY=/code/build/

COPY --from=web-serve-build /code/build "$APPLY_CONFIG__SOURCE_DIRECTORY"
COPY ./web-app-serve/apply-config.sh "$APPLY_CONFIG__APPLY_CONFIG_PATH"
```

**web-app-serve/apply-config.sh**
```bash
#!/bin/bash -xe

find "$DESTINATION_DIRECTORY" -type f -exec sed -i "s|\<APP_TITLE_PLACEHOLDER\>|$APP_TITLE|g" {} +
find "$DESTINATION_DIRECTORY" -type f -exec sed -i "s|\<APP_API_ENDPOINT_PLACEHOLDER\>|$APP_GRAPHQL_ENDPOINT|g" {} +
```
> NOTE:
> DESTINATION_DIRECTORY is the provided by the web-app-serve internal script
> Other environment are forwared as provided by the developer with the container

**web-app-serve/docker-compose.yml**
```yaml

name: my-org-my-best-dashboard

services:
  web-app-serve:
    build:
      context: ../
      target: web-app-serve
    environment:
      APPLY_CONFIG__ENABLE_DEBUG: true
      # Application specific environment variables.
      # Make sure this aligns with the placeholder variable from Dockerfile nginx-build stage
      APP_TITLE: ${APP_TITLE:- My Dashboard}
      APP_GRAPHQL_ENDPOINT: ${APP_GRAPHQL_ENDPOINT:-http://localhost:8000/graphql/}
    ports:
      - '8001:80'
    develop:
      watch:
        - action: sync+restart
          path: ../web-app-serve/apply-config.sh
          target: /code/apply-config.sh
```

To debug locally
```bash
docker compose -f web-app-serve/docker-compose.yml up
# Enable watch to apply ./web-app-serve/apply-config.sh to the container
```
