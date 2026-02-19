#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: jelicanin
# License: MIT | https://github.com/jelicanin/ProxmoxVE/raw/main/LICENSE
# Source: https://docs.postiz.com/self-hosting/docker-compose

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

DOCKER_SKIP_UPDATES="true" setup_docker
get_lxc_ip

msg_info "Downloading Postiz Stack Files"
mkdir -p /opt/postiz/dynamicconfig
$STD curl -fsSL https://raw.githubusercontent.com/gitroomhq/postiz-docker-compose/main/docker-compose.yaml -o /opt/postiz/docker-compose.yaml
$STD curl -fsSL https://raw.githubusercontent.com/gitroomhq/postiz-docker-compose/main/dynamicconfig/development-sql.yaml -o /opt/postiz/dynamicconfig/development-sql.yaml
msg_ok "Downloaded Postiz Stack Files"

POSTIZ_DB_PASSWORD="$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32)"
JWT_SECRET="$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 64)"
PUBLIC_URL="http://${LOCAL_IP}:4007"

msg_info "Configuring Postiz"
cat <<EOF >/opt/postiz/docker-compose.override.yaml
services:
  postiz:
    environment:
      MAIN_URL: "${PUBLIC_URL}"
      FRONTEND_URL: "${PUBLIC_URL}"
      NEXT_PUBLIC_BACKEND_URL: "${PUBLIC_URL}/api"
      JWT_SECRET: "${JWT_SECRET}"
      DATABASE_URL: "postgresql://postiz-user:${POSTIZ_DB_PASSWORD}@postiz-postgres:5432/postiz-db-local"
      DISABLE_REGISTRATION: "false"
      RUN_CRON: "true"

  postiz-postgres:
    environment:
      POSTGRES_PASSWORD: "${POSTIZ_DB_PASSWORD}"
      POSTGRES_USER: "postiz-user"
      POSTGRES_DB: "postiz-db-local"

  spotlight:
    profiles: ["debug"]

  temporal-ui:
    profiles: ["debug"]
EOF
msg_ok "Configured Postiz"

msg_info "Starting Postiz Stack (Patience)"
cd /opt/postiz
$STD docker compose up -d

msg_info "Waiting for Postiz to Start"
POSTIZ_CONTAINER_ID=""
for i in {1..90}; do
  POSTIZ_CONTAINER_ID="$(docker compose ps -q postiz 2>/dev/null)"
  if [[ -n "${POSTIZ_CONTAINER_ID}" ]]; then
    CONTAINER_STATUS="$(docker inspect --format '{{.State.Status}}' "${POSTIZ_CONTAINER_ID}" 2>/dev/null || true)"
    if [[ "${CONTAINER_STATUS}" == "running" ]]; then
      if curl -fsS http://127.0.0.1:4007 >/dev/null 2>&1; then
        msg_ok "Started Postiz Stack"
        break
      fi
    fi

    if [[ "${CONTAINER_STATUS}" == "exited" || "${CONTAINER_STATUS}" == "dead" ]]; then
      msg_error "Postiz container failed during startup"
      docker logs "${POSTIZ_CONTAINER_ID}" | tail -n 80
      exit 1
    fi
  fi

  if [[ "${i}" -eq 90 ]]; then
    msg_error "Timed out waiting for Postiz to become ready on port 4007"
    if [[ -n "${POSTIZ_CONTAINER_ID}" ]]; then
      docker logs "${POSTIZ_CONTAINER_ID}" | tail -n 80
    fi
    exit 1
  fi
  sleep 2
done

msg_info "Creating Postiz Credentials File"
cat <<EOF >~/postiz.creds
Postiz Information

URL: ${PUBLIC_URL}
Config Path: /opt/postiz/docker-compose.override.yaml

Default Login: No default credentials.
Open the URL and create your first account.
EOF
chmod 600 ~/postiz.creds
msg_ok "Created Postiz Credentials File"

motd_ssh
customize
cleanup_lxc
