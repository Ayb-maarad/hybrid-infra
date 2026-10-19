#!/bin/sh
set -u

# Normal-mode firewall verification for NSA LIL4.
# Run from the bastion host.
#
# This script does not change firewall rules. It only tests whether the normal
# traffic separation is already demonstrable.

BASTION_IP="${BASTION_IP:-10.20.0.2}"
NETBOX_IP="${NETBOX_IP:-10.10.0.2}"
ELK_IP="${ELK_IP:-10.10.0.3}"
WEB_IP="${WEB_IP:-10.20.0.3}"
PFSENSE_SITE1_IP="${PFSENSE_SITE1_IP:-10.10.0.1}"
PFSENSE_SITE2_IP="${PFSENSE_SITE2_IP:-10.20.0.1}"

SITE1_TESTER_USER="${SITE1_TESTER_USER:-esteban}"
SITE1_TESTER_PASS="${SITE1_TESTER_PASS:-root}"
SITE1_TESTER_HOST="${SITE1_TESTER_HOST:-10.10.0.2}"

SITE2_TESTER_USER="${SITE2_TESTER_USER:-lil4}"
SITE2_TESTER_PASS="${SITE2_TESTER_PASS:-root}"
SITE2_TESTER_HOST="${SITE2_TESTER_HOST:-10.20.0.3}"

TIMEOUT="${TIMEOUT:-5}"

PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0
SKIP_COUNT=0

green() { printf '\033[32m%s\033[0m\n' "$*"; }
red() { printf '\033[31m%s\033[0m\n' "$*"; }
yellow() { printf '\033[33m%s\033[0m\n' "$*"; }
blue() { printf '\033[34m%s\033[0m\n' "$*"; }

pass() {
    PASS_COUNT=$((PASS_COUNT + 1))
    green "PASS - $*"
}

fail() {
    FAIL_COUNT=$((FAIL_COUNT + 1))
    red "FAIL - $*"
}

warn() {
    WARN_COUNT=$((WARN_COUNT + 1))
    yellow "WARN - $*"
}

skip() {
    SKIP_COUNT=$((SKIP_COUNT + 1))
    yellow "SKIP - $*"
}

have_cmd() {
    command -v "$1" >/dev/null 2>&1
}

tcp_open() {
    host="$1"
    port="$2"

    if have_cmd nc; then
        nc -z -w "$TIMEOUT" "$host" "$port" >/dev/null 2>&1
        return $?
    fi

    timeout "$TIMEOUT" sh -c ":</dev/tcp/$host/$port" >/dev/null 2>&1
}

expect_open() {
    label="$1"
    host="$2"
    port="$3"

    if tcp_open "$host" "$port"; then
        pass "$label is reachable ($host:$port)"
    else
        fail "$label should be reachable but is blocked/refused ($host:$port)"
    fi
}

expect_closed() {
    label="$1"
    host="$2"
    port="$3"

    if tcp_open "$host" "$port"; then
        fail "$label should be restricted but is reachable ($host:$port)"
    else
        pass "$label is restricted as expected ($host:$port)"
    fi
}

http_ok() {
    url="$1"
    if have_cmd curl; then
        curl -I --max-time "$TIMEOUT" "$url" 2>/dev/null | head -n 1 | grep -Eq 'HTTP/[0-9.]+ (2|3)[0-9][0-9]'
        return $?
    fi
    return 1
}

expect_http_ok() {
    label="$1"
    url="$2"

    if http_ok "$url"; then
        pass "$label returns HTTP success ($url)"
    else
        fail "$label should return HTTP success but did not ($url)"
    fi
}

remote_test() {
    tester_user="$1"
    tester_pass="$2"
    tester_host="$3"
    host="$4"
    port="$5"

    if ! have_cmd sshpass; then
        return 2
    fi

    sshpass -p "$tester_pass" ssh \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout="$TIMEOUT" \
        "$tester_user@$tester_host" \
        "if command -v nc >/dev/null 2>&1; then nc -z -w $TIMEOUT $host $port; else timeout $TIMEOUT sh -c ':</dev/tcp/$host/$port'; fi" \
        >/dev/null 2>&1
}

remote_test_default() {
    host="$1"
    port="$2"

    remote_test "$SITE1_TESTER_USER" "$SITE1_TESTER_PASS" "$SITE1_TESTER_HOST" "$host" "$port"
}

remote_expect_open() {
    label="$1"
    host="$2"
    port="$3"

    remote_test_default "$host" "$port"
    rc=$?

    if [ "$rc" -eq 2 ]; then
        skip "$label from non-bastion VM (sshpass missing)"
        return
    fi

    if [ "$rc" -eq 0 ]; then
        pass "$label is reachable from non-bastion VM ($host:$port)"
    else
        fail "$label should be reachable from non-bastion VM but is blocked/refused ($host:$port)"
    fi
}

remote_expect_closed() {
    label="$1"
    host="$2"
    port="$3"

    remote_test_default "$host" "$port"
    rc=$?

    if [ "$rc" -eq 2 ]; then
        skip "$label from non-bastion VM (sshpass missing)"
        return
    fi

    if [ "$rc" -eq 0 ]; then
        fail "$label should be restricted from non-bastion VM but is reachable ($host:$port)"
    else
        pass "$label is restricted from non-bastion VM as expected ($host:$port)"
    fi
}

remote_expect_closed_from() {
    tester_label="$1"
    tester_user="$2"
    tester_pass="$3"
    tester_host="$4"
    label="$5"
    host="$6"
    port="$7"

    remote_test "$tester_user" "$tester_pass" "$tester_host" "$host" "$port"
    rc=$?

    if [ "$rc" -eq 2 ]; then
        skip "$label from $tester_label (sshpass missing)"
        return
    fi

    if [ "$rc" -eq 0 ]; then
        fail "$label should be restricted from $tester_label but is reachable ($host:$port)"
    else
        pass "$label is restricted from $tester_label as expected ($host:$port)"
    fi
}

print_manual_remote_commands() {
    cat <<EOF

Manual non-bastion checks if sshpass is not installed:

ssh $SITE1_TESTER_USER@$SITE1_TESTER_HOST
nc -vz $WEB_IP 80      # should succeed
nc -vz $WEB_IP 22      # should fail/timeout

ssh $SITE2_TESTER_USER@$SITE2_TESTER_HOST
nc -vz $ELK_IP 5601    # should fail/timeout if tested cross-site or with host firewall/VLAN
nc -vz $ELK_IP 9200    # should fail/timeout if tested cross-site or with host firewall/VLAN
nc -vz $NETBOX_IP 8001 # should fail/timeout if tested cross-site or with host firewall/VLAN
exit
EOF
}

blue "== Normal firewall verification =="
printf 'Bastion:       %s\n' "$BASTION_IP"
printf 'pfSense S1:    %s\n' "$PFSENSE_SITE1_IP"
printf 'pfSense S2:    %s\n' "$PFSENSE_SITE2_IP"
printf 'NetBox:        %s\n' "$NETBOX_IP"
printf 'ELK:           %s\n' "$ELK_IP"
printf 'Web:           %s\n' "$WEB_IP"
printf 'Site 1 tester: %s@%s\n' "$SITE1_TESTER_USER" "$SITE1_TESTER_HOST"
printf 'Site 2 tester: %s@%s\n' "$SITE2_TESTER_USER" "$SITE2_TESTER_HOST"
echo

blue "== Firewall presence and DNS/gateway reachability =="
expect_open "pfSense Site 1 DNS" "$PFSENSE_SITE1_IP" 53
expect_open "pfSense Site 2 DNS" "$PFSENSE_SITE2_IP" 53

blue "== Required flows from bastion =="
expect_open "Bastion to NetBox SSH" "$NETBOX_IP" 22
expect_open "Bastion to ELK SSH" "$ELK_IP" 22
expect_open "Bastion to Web SSH" "$WEB_IP" 22
expect_http_ok "Web internal service" "http://$WEB_IP"

blue "== Sensitive service exposure from bastion =="
warn "Bastion is an admin entry point, so sensitive ports may be reachable from here."
if tcp_open "$NETBOX_IP" 8001; then
    warn "NetBox 8001 is reachable from bastion, acceptable for admin if intended."
else
    warn "NetBox 8001 is not reachable from bastion; service may be stopped or exposed through another port."
fi
if tcp_open "$ELK_IP" 5601; then
    warn "Kibana 5601 is reachable from bastion, acceptable for admin if intended."
else
    warn "Kibana 5601 is not reachable from bastion; service may be stopped or firewalled."
fi

blue "== Separation tests from non-bastion VM =="
remote_expect_open "Non-bastion to web HTTP" "$WEB_IP" 80
remote_expect_closed "Non-bastion to web SSH" "$WEB_IP" 22
remote_expect_closed_from "Site 2 non-bastion VM" "$SITE2_TESTER_USER" "$SITE2_TESTER_PASS" "$SITE2_TESTER_HOST" "Non-bastion to Kibana" "$ELK_IP" 5601
remote_expect_closed_from "Site 2 non-bastion VM" "$SITE2_TESTER_USER" "$SITE2_TESTER_PASS" "$SITE2_TESTER_HOST" "Non-bastion to Elasticsearch API" "$ELK_IP" 9200
remote_expect_closed_from "Site 2 non-bastion VM" "$SITE2_TESTER_USER" "$SITE2_TESTER_PASS" "$SITE2_TESTER_HOST" "Non-bastion to NetBox app port" "$NETBOX_IP" 8001

if ! have_cmd sshpass; then
    print_manual_remote_commands
fi

echo
blue "== Summary =="
printf 'PASS: %s\n' "$PASS_COUNT"
printf 'FAIL: %s\n' "$FAIL_COUNT"
printf 'WARN: %s\n' "$WARN_COUNT"
printf 'SKIP: %s\n' "$SKIP_COUNT"

if [ "$FAIL_COUNT" -eq 0 ]; then
    green "Normal firewall demonstration passed."
    exit 0
fi

red "Normal firewall demonstration has failing checks."
exit 1
