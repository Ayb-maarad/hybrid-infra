#!/usr/bin/env bash
set -euo pipefail

sudo apt update
sudo apt install -y \
  ansible \
  python3-pip \
  sshpass \
  rsync

ansible-galaxy collection install -f -r requirements.yml

python3 -m pip install --user --break-system-packages \
  pynetbox \
  pyyaml \
  requests
