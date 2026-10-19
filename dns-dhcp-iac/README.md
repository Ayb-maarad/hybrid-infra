# DNS / DHCP IaC for pfSense

This module configures the project DNS and DHCP setup from the bastion host.

It uses one Ansible playbook:

```text
ansible/playbook.yml
```

The playbook has two tagged parts:

- `pfsense`: configures DHCP, Unbound DNS Resolver, host overrides and inter-site DNS forwarding on pfSense.
- `clients`: configures static Linux VMs so they use pfSense as their DNS resolver.

## Topology

| Site | pfSense DNS/Gateway | LAN Network | Domain |
|---|---:|---|---|
| Site 1 / DC1 | 10.10.0.1 | 10.10.0.0/24 | site1.local |
| Site 2 / DC2 | 10.20.0.1 | 10.20.0.0/24 | site2.local |

## DNS Records

Configured in `ansible/vars.yml`.

| Name | IP | Site |
|---|---:|---|
| netbox.site1.local | 10.10.0.2 | Site 1 |
| elastic.site1.local | 10.10.0.3 | Site 1 |
| bastion.site2.local | 10.20.0.2 | Site 2 |
| web.site2.local | 10.20.0.3 | Site 2 |

## DHCP

| Site | Range | Gateway | DNS | Domain |
|---|---|---:|---:|---|
| Site 1 | 10.10.0.100 - 10.10.0.200 | 10.10.0.1 | 10.10.0.1 | site1.local |
| Site 2 | 10.20.0.100 - 10.20.0.200 | 10.20.0.1 | 10.20.0.1 | site2.local |

## Inter-Site DNS

Each pfSense forwards the remote domain to the remote pfSense DNS:

| From | Domain | Forward To |
|---|---|---:|
| Site 1 pfSense | site2.local | 10.20.0.1 |
| Site 2 pfSense | site1.local | 10.10.0.1 |

This allows a VM in Site 1 to resolve names like `web.site2.local`, and a VM in Site 2 to resolve names like `elastic.site1.local`.

## Linux DNS Clients

Static Linux VMs are listed in `ansible/inventory.ini` under `[dns_clients]`.

The playbook writes this systemd-resolved drop-in on each Linux client:

```text
/etc/systemd/resolved.conf.d/10-internal-dns.conf
```

It forces the client to use the local pfSense DNS and routes both internal zones through internal DNS:

```ini
[Resolve]
DNS=
DNS=<site-pfsense-ip>
Domains=
Domains=~site1.local ~site2.local <local-site-domain>
FallbackDNS=
```

The empty `DNS=` and `Domains=` lines reset previous values such as `8.8.8.8` or `1.1.1.1`.

## Run

Run from the bastion host.

```bash
cd ~/dns-dhcp-iac/ansible
```

Configure everything:

```bash
ansible-playbook -i inventory.ini playbook.yml
```

Configure only pfSense:

```bash
ansible-playbook -i inventory.ini playbook.yml --tags pfsense -k
```

Configure only Linux DNS clients:

```bash
ansible-playbook -i inventory.ini playbook.yml --tags clients
```

## Validation

From a Site 1 VM:

```bash
dig elastic.site1.local +short
dig netbox.site1.local +short
dig bastion.site2.local +short
dig web.site2.local +short
```

Expected:

```text
10.10.0.3
10.10.0.2
10.20.0.2
10.20.0.3
```

Check service connectivity across sites:

```bash
ping -c 3 web.site2.local
curl http://web.site2.local
```

Useful direct pfSense tests:

```bash
dig @10.10.0.1 elastic.site1.local +short
dig @10.10.0.1 bastion.site2.local +short
dig @10.20.0.1 web.site2.local +short
dig @10.20.0.1 elastic.site1.local +short
```

If direct local DNS works but a normal `dig name.local` does not, check the Linux client resolver:

```bash
resolvectl status
cat /etc/systemd/resolved.conf.d/10-internal-dns.conf
```
