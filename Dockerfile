FROM nginx:1

LABEL maintainer="Togglecorp"
LABEL org.opencontainers.image.source="https://github.com/toggle-corp/web-app-serve"

ARG BIOME_VERSION=2.0.6

RUN curl -L "https://github.com/biomejs/biome/releases/download/@biomejs/biome@${BIOME_VERSION}/biome-linux-x64" -o /usr/local/bin/biome && \
    chmod +x /usr/local/bin/biome

# NOTE: Used by apply-config.sh
ENV APPLY_CONFIG__ENABLE_DEBUG=false
ENV APPLY_CONFIG__DEBUG_USE_BIOME=true

ENV APPLY_CONFIG__DESTINATION_DIRECTORY=/usr/share/nginx/html/

COPY ./src/ /web-app-serve/
RUN ln -sf /web-app-serve/apply-config.sh /docker-entrypoint.d/apply-config.sh && \
    mkdir /etc/nginx/templates && \
    ln -sf /web-app-serve/nginx.conf.template /etc/nginx/templates/default.conf.template
