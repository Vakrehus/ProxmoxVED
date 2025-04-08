#!/usr/bin/env bash
# Copyright (c) 2021-2025 community-scripts ORG
# Author: Freika | Co-Author: [DeinName]
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/Freika/dawarich

source /dev/stdin <<< "$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y \
  curl \
  sudo \
  mc \
  build-essential \
  git \
  libpq-dev \
  postgresql-client \
  libxml2-dev \
  libxslt1-dev \
  libyaml-dev \
  imagemagick \
  tzdata \
  ruby-full \
  nodejs \
  npm
msg_ok "Installed Dependencies"

msg_info "Installing Yarn"
npm install -g yarn@1.22.19
msg_ok "Installed Yarn"

msg_info "Installing Bundler"
gem update --system
gem install bundler -v 2.5.21
msg_ok "Installed Bundler"

msg_info "Installing Dawarich"
cd /opt
git clone https://github.com/Freika/dawarich.git
cd dawarich
bundle config set --local path 'vendor/bundle'
bundle config set --local without 'development test'
bundle install --jobs 4 --retry 3
SECRET_KEY_BASE_DUMMY=1 bundle exec rake assets:precompile
RELEASE=$(curl -s https://api.github.com/repos/Freika/dawarich/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3) }')
echo "${RELEASE}" > /opt/dawarich_version.txt
msg_ok "Installed Dawarich"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/dawarich.service
[Unit]
Description=Dawarich Rails App
After=network.target

[Service]
WorkingDirectory=/opt/dawarich
ExecStart=/usr/local/bin/bundle exec rails server -e production -b 0.0.0.0
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now dawarich.service
msg_ok "Created Service"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
