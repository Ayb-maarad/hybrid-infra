#!/bin/sh
set -eu

MODE="${1:-}"

if [ "$MODE" != "soft" ] && [ "$MODE" != "hard" ] && [ "$MODE" != "off" ]; then
    echo "Usage: $0 soft|hard|off"
    exit 1
fi

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
PLAYBOOK="$SCRIPT_DIR/ansible/playbook.yml"
INVENTORY="$SCRIPT_DIR/ansible/inventory.ini"

echo "Running kill-switch2 in mode: $MODE"
ansible-playbook -i "$INVENTORY" "$PLAYBOOK" -e "kill_switch_state=$MODE"

