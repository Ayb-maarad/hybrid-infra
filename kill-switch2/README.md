# Kill Switch 2

Kill Switch 2 is a pfSense-first isolation mechanism for the NSA LIL4 infrastructure.

It does not replace normal firewall policy. It adds temporary, clearly marked pfSense floating rules, then removes only those rules when disabled.

## Goal

Keep admin access through the bastion while isolating sensitive internal services.

This folder covers the `incident_killswitch` achievement:

```text
An emergency shutdown (kill switch) strategy exists that does not prevent recovery.
```

It also supports the `incident_recovery` achievement by documenting how to return to the normal state after the incident mode.

Kept available:

- External admin to bastion SSH
- Bastion to internal VMs for admin access
- Internal DNS through pfSense
- Web demo service on `web.site2.local:80`

Restricted:

- Direct user access to NetBox admin/API ports
- Direct user access to ELK/Kibana/Elasticsearch admin ports
- Direct user access to SSH/sensitive service ports

## Modes

| Mode | Effect |
|---|---|
| `soft` | Add temporary pfSense firewall rules. VPN stays up. Recommended for demos. |
| `hard` | Same as `soft`, then attempts to stop OpenVPN on pfSense Site 2. |
| `off` | Remove all rules marked `KILL_SWITCH2`, then attempts to start OpenVPN on pfSense Site 2. |

OpenVPN start/stop is non-blocking because pfSense OpenVPN paths may differ between installs.

### Soft Mode

Soft mode is the preferred demonstration mode.

It keeps the inter-site VPN alive but isolates sensitive services from normal non-bastion VMs.

Expected result:

- Bastion can still administer internal VMs.
- Web demo remains reachable on HTTP port `80`.
- Non-bastion VMs cannot reach sensitive admin/service ports.
- Recovery is simple with mode `off`.

### Hard Mode

Hard mode is the emergency mode.

It first applies the same firewall isolation as `soft`, then attempts to stop OpenVPN on pfSense Site 2:

```bash
service openvpn onestop
```

Expected result:

- Sensitive services are protected by firewall rules.
- The VPN site-to-site may be cut.
- Bastion/admin access should remain the recovery path.

Use this only when you want to demonstrate a stronger emergency shutdown.

### Off Mode

Off mode is the recovery mode.

It removes only pfSense rules whose description contains:

```text
KILL_SWITCH2
```

Then it attempts to restart OpenVPN on pfSense Site 2:

```bash
service openvpn onestart
```

This means the playbook does not delete unrelated firewall rules.

## Topology

| Host | IP | Role |
|---|---:|---|
| pfSense Site 1 | 10.10.0.1 | Firewall, DNS, VPN |
| NetBox | 10.10.0.2 | IPAM |
| ELK | 10.10.0.3 | Logs, Kibana, Elasticsearch |
| pfSense Site 2 | 10.20.0.1 | Firewall, DNS, VPN |
| Bastion | 10.20.0.2 | Admin entry point |
| Web | 10.20.0.3 | Internal demo web |

## Files

```text
kill-switch2/
  ansible/
    inventory.ini
    playbook.yml
    vars.yml
    templates/
      pfsense_kill_switch.php.j2
  kill-switch2.sh
  verify-normal-firewall.sh
```

## Run

Run from the bastion host:

```bash
cd ~/kill-switch2/ansible
```

Enable soft mode:

```bash
ansible-playbook -i inventory.ini playbook.yml -e kill_switch_state=soft
```

Enable hard mode:

```bash
ansible-playbook -i inventory.ini playbook.yml -e kill_switch_state=hard
```

Disable and restore:

```bash
ansible-playbook -i inventory.ini playbook.yml -e kill_switch_state=off
```

The helper script can also be used:

```bash
../kill-switch2.sh soft
../kill-switch2.sh hard
../kill-switch2.sh off
```

## Demonstration Procedure

### 1. Show Normal State

From the bastion:

```bash
cd ~/kill-switch2
sh verify-normal-firewall.sh
```

If the normal firewall is too permissive, the script may show failures such as:

```text
Non-bastion to web SSH should be restricted
Non-bastion to Kibana should be restricted
Non-bastion to NetBox app port should be restricted
```

This proves why the kill switch is useful.

### 2. Enable Soft Kill Switch

```bash
cd ~/kill-switch2/ansible
ansible-playbook -i inventory.ini playbook.yml -e kill_switch_state=soft
```

Then verify:

```bash
cd ~/kill-switch2
sh verify-normal-firewall.sh
```

Expected result:

```text
PASS: 11
FAIL: 0
Normal firewall demonstration passed.
```

This demonstrates the emergency isolation strategy while keeping recovery possible.

### 3. Optional Hard Kill Switch Demo

Only run this if you want to demonstrate VPN shutdown.

```bash
cd ~/kill-switch2/ansible
ansible-playbook -i inventory.ini playbook.yml -e kill_switch_state=hard
```

Then verify that sensitive ports are still blocked:

```bash
cd ~/kill-switch2
sh verify-normal-firewall.sh
```

The VPN stop command is best-effort. If OpenVPN paths differ on pfSense, the firewall isolation can still be valid even if the VPN command prints a warning.

### 4. Recover

```bash
cd ~/kill-switch2/ansible
ansible-playbook -i inventory.ini playbook.yml -e kill_switch_state=off
```

This removes the temporary kill-switch rules and attempts to restart OpenVPN.

After `off`, running the verification script may show the previous normal-state failures again. That is expected if the permanent firewall policy is still permissive.

## What Is Blocked

The temporary pfSense rules block traffic from these user networks:

```text
10.10.0.0/24
10.20.0.0/24
```

to these sensitive services:

| Service | IP | Ports |
|---|---:|---|
| NetBox | 10.10.0.2 | 80, 443, 8000, 8001 |
| ELK | 10.10.0.3 | 22, 443, 5601, 9200 |
| Web admin ports | 10.20.0.3 | 22, 443 |

The bastion `10.20.0.2` is explicitly allowed before the block rules.

Port `80` on the web VM is not blocked in soft mode, so demo access to `http://web.site2.local` remains available.

## Validation

Before using the kill switch, you can verify whether the normal firewall policy is already demonstrable:

```bash
cd ~/kill-switch2
sh verify-normal-firewall.sh
```

The script checks:

- pfSense DNS/gateway reachability on both sites.
- Bastion admin access to internal VMs.
- Web HTTP access.
- Sensitive-port separation from a non-bastion VM when `sshpass` is available.

By default, the script uses two non-bastion testers:

- Site 1 tester: `esteban@10.10.0.2`, password `root`, used to test access to Site 2 web.
- Site 2 tester: `lil4@10.20.0.3`, password `root`, used to test access to Site 1 NetBox/ELK.

Override them if needed:

```bash
SITE1_TESTER_USER=lil4 SITE1_TESTER_PASS=root SITE1_TESTER_HOST=10.10.0.3 \
SITE2_TESTER_USER=lil4 SITE2_TESTER_PASS=root SITE2_TESTER_HOST=10.20.0.3 \
sh verify-normal-firewall.sh
```

After `soft` mode, from a non-bastion client:

```bash
curl -I --max-time 5 http://10.10.0.2:8001
curl -I --max-time 5 http://10.10.0.3:5601
```

These should timeout or be refused.

From the bastion:

```bash
curl -I --max-time 5 http://10.20.0.3
curl -I --max-time 5 http://web.site2.local
```

These should still return:

```text
HTTP/1.1 200 OK
```

After `off` mode, sensitive services should be reachable again if the service itself is running.

## Manual Validation Commands

From the bastion:

```bash
curl -I --max-time 5 http://10.20.0.3
nc -vz 10.10.0.2 22
nc -vz 10.10.0.3 22
nc -vz 10.20.0.3 22
```

These are expected to work because the bastion is the admin entry point.

From a non-bastion VM on Site 2, for example `10.20.0.3`, test Site 1 sensitive services:

```bash
nc -vz 10.10.0.2 8001
nc -vz 10.10.0.3 5601
nc -vz 10.10.0.3 9200
```

In `soft` or `hard` mode, these should fail, timeout, or be refused by the firewall.

From a non-bastion VM on Site 1, test Site 2 web:

```bash
curl -I --max-time 5 http://10.20.0.3
nc -vz 10.20.0.3 22
```

Expected:

- HTTP `80` works.
- SSH `22` is blocked for non-bastion VMs.

## Recovery Procedure

Use this when you want to return to the normal state.

### 1. Run Off Mode

```bash
cd ~/kill-switch2/ansible
ansible-playbook -i inventory.ini playbook.yml -e kill_switch_state=off
```

### 2. Check Bastion Access

From the bastion:

```bash
nc -vz 10.10.0.2 22
nc -vz 10.10.0.3 22
nc -vz 10.20.0.3 22
```

### 3. Check Web Demo

```bash
curl -I --max-time 5 http://10.20.0.3
curl -I --max-time 5 http://web.site2.local
```

Expected:

```text
HTTP/1.1 200 OK
```

### 4. Check OpenVPN Manually If Needed

If hard mode was used, OpenVPN may need manual verification on pfSense Site 2.

SSH to pfSense Site 2:

```bash
ssh admin@10.20.0.1
```

Check OpenVPN:

```sh
ps aux | grep openvpn
```

Try to start it manually if needed:

```sh
service openvpn onestart
```

Then test inter-site routing again from the bastion or another VM:

```bash
ping -c 3 10.10.0.1
ping -c 3 10.10.0.2
dig @10.10.0.1 netbox.site1.local +short
```

### 5. Restore pfSense Config Backup If Needed

Before each change, the playbook creates a backup on pfSense:

```text
/cf/conf/config.xml.kill-switch2.YYYYMMDD-HHMMSS
```

If recovery with `off` is not enough, restore the previous pfSense config from the pfSense console or SSH. Example:

```sh
cp /cf/conf/config.xml.kill-switch2.YYYYMMDD-HHMMSS /cf/conf/config.xml
/etc/rc.reload_all
```

Replace `YYYYMMDD-HHMMSS` with the backup timestamp you want to restore.

## Achievement Evidence

For `incident_killswitch`, show:

1. `soft` mode applied successfully.
2. `verify-normal-firewall.sh` returns `FAIL: 0`.
3. Sensitive access from non-bastion VMs is blocked.
4. Bastion and web demo access still work.

For `incident_recovery`, show:

1. `off` mode runs successfully.
2. Temporary rules marked `KILL_SWITCH2` are removed.
3. Web demo and admin access still work.
4. OpenVPN can be restarted or checked manually.

The important point is that the emergency shutdown is reversible and does not lock out the recovery path.

## pfSense Checks

On pfSense, temporary rules are marked with:

```text
KILL_SWITCH2
```

The playbook removes only rules containing this marker.

If something looks wrong, run mode `off`:

```bash
ansible-playbook -i inventory.ini playbook.yml -e kill_switch_state=off
```
