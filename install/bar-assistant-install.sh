#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: bvdberg01
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/karlomikus/bar-assistant
# Source: https://github.com/karlomikus/vue-salt-rim
# Source: https://www.meilisearch.com/

source /dev/stdin <<< "$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y \
  php-{ffi,opcache,redis,zip,pdo-sqlite,bcmath,pdo,curl,dom,fpm} \
  composer \
  redis-server \
  npm \
  nginx
msg_ok "Installed Dependencies"

msg_info "Installing MeiliSearch"
cd /opt
RELEASE_MEILISEARCH=$(curl -s https://api.github.com/repos/meilisearch/meilisearch/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3) }')
curl -fsSL https://github.com/meilisearch/meilisearch/releases/latest/download/meilisearch.deb -o meilisearch.deb
$STD dpkg -i meilisearch.deb
curl -fsSL https://raw.githubusercontent.com/meilisearch/meilisearch/latest/config.toml -o /etc/meilisearch.toml
MASTER_KEY=$(openssl rand -base64 12)
sed -i \
    -e 's|^env =.*|env = "production"|' \
    -e "s|^# master_key =.*|master_key = \"$MASTER_KEY\"|" \
    -e 's|^db_path =.*|db_path = "/var/lib/meilisearch/data"|' \
    -e 's|^dump_dir =.*|dump_dir = "/var/lib/meilisearch/dumps"|' \
    -e 's|^snapshot_dir =.*|snapshot_dir = "/var/lib/meilisearch/snapshots"|' \
    -e 's|^# no_analytics = true|no_analytics = true|' \
    -e 's|^http_addr =.*|http_addr = "0.0.0.0:7700"|' \
    /etc/meilisearch.toml
echo "${RELEASE_MEILISEARCH}" >/opt/meilisearch_version.txt
msg_ok "Installed MeiliSearch"

msg_info "Creating MeiliSearch service"
cat <<EOF >/etc/systemd/system/meilisearch.service
[Unit]
Description=Meilisearch
After=network.target

[Service]
ExecStart=/usr/bin/meilisearch --config-file-path /etc/meilisearch.toml
Restart=always

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now meilisearch
msg_ok "Created Service MeiliSearch"

msg_info "Installing Bar Assistant"
RELEASE_BARASSISTANT=$(curl -s https://api.github.com/repos/karlomikus/bar-assistant/releases/latest | grep "tag_name" | awk '{print substr($2, 3, length($2)-4) }')
cd /opt
curl -fsSL "https://github.com/karlomikus/bar-assistant/archive/refs/tags/v${RELEASE_BARASSISTANT}.zip" -o barassistant.zip
unzip -q barassistant.zip
mv /opt/bar-assistant-${RELEASE_BARASSISTANT}/ /opt/bar-assistant
cd /opt/bar-assistant
cp /opt/bar-assistant/.env.dist /opt/bar-assistant/.env
MeiliSearch_API_KEY=$(curl -s -X GET 'http://127.0.0.1:7700/keys' -H "Authorization: Bearer $MASTER_KEY" | grep -o '"key":"[^"]*"' | head -n 1 | sed 's/"key":"//;s/"//')
MeiliSearch_API_KEY_UID=$(curl -s -X GET 'http://127.0.0.1:7700/keys' -H "Authorization: Bearer $MASTER_KEY" | grep -o '"uid":"[^"]*"' | head -n 1 | sed 's/"uid":"//;s/"//')
sed -i -e "s|^MEILISEARCH_HOST=|MEILISEARCH_HOST=http://127.0.0.1:7700|" \
    -e "s|^MEILISEARCH_KEY=|MEILISEARCH_KEY=${MASTER_KEY}|" \
    -e "s|^MEILISEARCH_API_KEY=|MEILISEARCH_API_KEY=${MeiliSearch_API_KEY}|" \
    -e "s|^MEILISEARCH_API_KEY_UID=|MEILISEARCH_API_KEY_UID=${MeiliSearch_API_KEY_UID}|" \
    /opt/bar-assistant/.env
$STD composer install --no-interaction
$STD php artisan key:generate
touch storage/bar-assistant/database.ba3.sqlite
$STD php artisan migrate --force
$STD php artisan storage:link
$STD php artisan bar:setup-meilisearch
$STD php artisan scout:sync-index-settings
$STD php artisan config:cache
$STD php artisan route:cache
$STD php artisan event:cache
echo "${RELEASE_BARASSISTANT}" >/opt/${APPLICATION}_version.txt
msg_ok "Installed Bar Assistant"

msg_info "Installing Salt Rim"
RELEASE_SALTRIM=$(curl -s https://api.github.com/repos/karlomikus/vue-salt-rim/releases/latest | grep "tag_name" | awk '{print substr($2, 3, length($2)-4) }')
cd /opt
curl -fsSL "https://github.com/karlomikus/vue-salt-rim/archive/refs/tags/v${RELEASE_SALTRIM}.zip" -o saltrim.zip
unzip -q saltrim.zip
mv /opt/vue-salt-rim-${RELEASE_SALTRIM}/ /opt/vue-salt-rim
cd /opt/vue-salt-rim
LOCAL_IP=$(hostname -I | awk '{print $1}')
cat <<EOF >/opt/vue-salt-rim/public/config.js
window.srConfig = {}
window.srConfig.API_URL = "http://${LOCAL_IP}"
window.srConfig.MEILISEARCH_URL = "http://127.0.0.1:7700"
EOF
$STD npm install
$STD npm run build
echo "${RELEASE_SALTRIM}" >/opt/vue-salt-rim_version.txt
msg_ok "Installed Salt Rim"

msg_info "Creating Service"
cat <<EOF >/etc/nginx/sites-available/barassistant.conf
server {
    listen 80;
    listen [::]:80;
    server_name example.com;
    root /opt/bar-assistant/public;

    add_header X-Frame-Options "SAMEORIGIN";
    add_header X-Content-Type-Options "nosniff";

    index index.php;

    charset utf-8;

    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }

    location = /favicon.ico { access_log off; log_not_found off; }
    location = /robots.txt  { access_log off; log_not_found off; }

    error_page 404 /index.php;

    location ~ ^/index\.php(/|$) {
        fastcgi_pass unix:/var/run/php/php8.2-fpm.sock;
        fastcgi_param SCRIPT_FILENAME $realpath_root$fastcgi_script_name;
        include fastcgi_params;
        fastcgi_hide_header X-Powered-By;
    }

    location ~ /\.(?!well-known).* {
        deny all;
    }
}
EOF

cat <<EOF >/etc/nginx/sites-available/saltrim.conf
server {
    listen 8080 default_server;
    listen [::]:8080 default_server;
    server_name _;
    root /opt/vue-salt-rim/dist;

    location / {
        try_files $uri $uri/ /index.html;
    }
}
EOF

ln -s /etc/nginx/sites-available/barassistant.conf /etc/nginx/sites-enabled/
ln -s /etc/nginx/sites-available/saltrim.conf /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
$STD systemctl reload nginx
msg_ok "Created Service"

motd_ssh
customize

msg_info "Cleaning up"
rm -rf /opt/meilisearch.deb
rm -rf "/opt/barassistant.zip"
rm -rf "/opt/saltrim.zip"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
