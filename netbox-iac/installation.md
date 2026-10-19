#  NetBox IaC Hybrid Infrastructure Bootstrap

## 1. Objectif

Ce dépôt permet de reconstruire intégralement une instance **NetBox bare-metal** dans un environnement hybride :

* **1 site Cloud**
* **1 site On-Prem**
* **1 Bastion d'administration**
* déploiement et configuration via **Ansible**
* peuplement des données via **NetBox Data as Code**

La philosophie retenue est la suivante :

> aucune dépendance à la configuration manuelle UI hormis consultation ponctuelle.

L'objectif final est qu'une VM vierge puisse être reconstruite via code avec :

* installation système,
* installation NetBox,
* configuration PostgreSQL/Redis/Gunicorn/Nginx,
* création du superuser,
* génération ou récupération du token API,
* import des données d'infrastructure.

---

## 2. Architecture globale du process

```text
Machine locale -> Bastion Ubuntu (control node) -> VM NetBox privée
```

Le bastion est la machine officielle d'exécution de :

* Ansible
* scripts Python d'import API
* synchronisations futures d'inventaire

---

## 3. Structure du dépôt

```text
netbox-iac/
├── ansible.cfg
├── bootstrap-bastion.sh
├── requirements.yml
└── ansible/
│   ├── inventory.ini
│   ├── playbook.yml
│   ├── pfsense-playbook.yml
│   ├── group_vars/
│   │   ├── all/
│   │   │   └── vault.yml
│   │   ├── firewalls.yml
│   │   ├── netbox.yml
│   │   └── netbox_data.yml
│   └── roles/
│       ├── base/
│       ├── postgresql/
│       ├── redis/
│       ├── netbox/
│       ├── systemd/
│       ├── nginx/
│       ├── bootstrap_api/
│       └── netbox_seed/
```

---

## 4. Préparation du bastion (Control Node)

### Installation automatique

```bash
chmod +x bootstrap-bastion.sh
./bootstrap-bastion.sh
```

### Ce script installe

* ansible
* python3-pip
* sshpass
* rsync
* collection `community.postgresql`
* collection `netbox.netbox`
* collection `pfsensible.core`
* librairies Python `pynetbox`, `pyyaml`, `requests`

### Vérification

```bash
ansible --version
ansible-galaxy collection list | grep -E 'community.postgresql|netbox.netbox|pfsensible.core'
python3 -m pip list --user | grep pynetbox
```

---

## 5. Inventory Ansible

Fichier : `ansible/inventory.ini`

Contient :

* IP privée de la VM NetBox
* IP des firewalls pfSense
* utilisateur SSH réel

Les mots de passe ne doivent pas être stockés dans l'inventaire. Ils sont fournis par Ansible Vault.

Test de connectivité :

```bash
ansible -i ansible/inventory.ini netbox -m ping -k
```

ou

```bash
ansible -i ansible/inventory.ini netbox -m ping
```

si mdp déjà stocké.

---

## 6. Variables et secrets

### Variables NetBox

Fichier : `ansible/group_vars/netbox.yml`

Contient notamment :

* version NetBox
* admin user bootstrap
* chemins NetBox
* port Gunicorn

Les valeurs sensibles de ce fichier référencent des variables `vault_*`.

### Données NetBox

Fichier : `ansible/group_vars/netbox_data.yml`

Contient les données injectées via l'API NetBox :

* régions et sites
* prefixes IP
* rôles, constructeurs, types et plateformes
* équipements pfSense et hôtes Proxmox
* interfaces virtuelles pfSense `WAN`, `LAN`, `DMZ`, `VPN`
* machines virtuelles applicatives
* adresses IP et affectation aux interfaces pfSense
* services
* tunnel VPN site-to-site

### Secrets Ansible Vault

Fichier chiffré :

```text
ansible/group_vars/all/vault.yml
```

Il contient notamment :

* mot de passe PostgreSQL
* `SECRET_KEY` NetBox
* mot de passe admin NetBox
* `API_TOKEN_PEPPERS`
* token API NetBox de fallback
* mot de passe pfSense
* clé statique OpenVPN

Le fichier de mot de passe Vault local est :

```text
ansible/.vault-pass
```

Ce fichier doit rester local et confidentiel.

Commandes utiles :

```bash
ansible-vault view ansible/group_vars/all/vault.yml
ansible-vault edit ansible/group_vars/all/vault.yml
ansible-vault rekey ansible/group_vars/all/vault.yml
```

La configuration `ansible.cfg` pointe vers `ansible/.vault-pass`, donc les commandes Ansible le chargent automatiquement si le fichier existe.

---

## 7. Ordre d'exécution officiel du playbook

### Vérification syntaxe

```bash
ansible-playbook -i ansible/inventory.ini ansible/playbook.yml --syntax-check
```

### Déploiement complet

```bash
ansible-playbook -i ansible/inventory.ini ansible/playbook.yml -k -K
```

### Déploiement par rôle (debug fin)

```bash
ansible-playbook -i ansible/inventory.ini ansible/playbook.yml -k -K --tags base
ansible-playbook -i ansible/inventory.ini ansible/playbook.yml -k -K --tags postgresql
ansible-playbook -i ansible/inventory.ini ansible/playbook.yml -k -K --tags redis
ansible-playbook -i ansible/inventory.ini ansible/playbook.yml -k -K --tags netbox
ansible-playbook -i ansible/inventory.ini ansible/playbook.yml -k -K --tags systemd
ansible-playbook -i ansible/inventory.ini ansible/playbook.yml -k -K --tags nginx
ansible-playbook -i ansible/inventory.ini ansible/playbook.yml -k -K --tags bootstrap_api
ansible-playbook -i ansible/inventory.ini ansible/playbook.yml -k -K --tags netbox_seed
```

---

## 8. Ce que fait chaque rôle

### base

Installe les dépendances Python et compilation minimales.

### postgresql

Installe PostgreSQL, crée user DB et base NetBox.

### redis

Installe Redis backend cache/tasks.

### netbox

* télécharge NetBox
* crée venv Python
* installe requirements
* déploie configuration.py
* lance migrate
* lance collectstatic
* ajuste permissions static

### systemd

Crée et active :

* `netbox.service`
* `netbox-rq.service`

### nginx

Expose :

* `/static/`
* reverse proxy vers Gunicorn `:8001`

### bootstrap_api

* crée superuser admin
* génère ou récupère le token API
* expose le token comme variable Ansible runtime pour `netbox_seed`
* masque les valeurs sensibles avec `no_log`

### netbox_seed

Injecte le référentiel d'infrastructure dans NetBox via l'API.

---

## 9. Commandes de debug indispensables

### Connectivité SSH Ansible

```bash
ansible -i ansible/inventory.ini netbox -m ping -k
```

### Vérification services

```bash
systemctl status postgresql --no-pager
systemctl status redis-server --no-pager
systemctl status netbox --no-pager
systemctl status netbox-rq --no-pager
systemctl status nginx --no-pager
```

### Journaux NetBox

```bash
sudo journalctl -u netbox -n 80 --no-pager
sudo journalctl -u netbox-rq -n 80 --no-pager
sudo journalctl -u nginx -n 80 --no-pager
```

### Vérification écoute réseau

```bash
ss -lntp | grep 8001
ss -lntp | grep ':80'
```

### Vérification web locale

```bash
curl -I http://127.0.0.1:8001
curl -I http://127.0.0.1
curl -I http://127.0.0.1/static/setmode.js
```

### Vérification espace disque

```bash
df -h
sudo du -xh / --max-depth=1 2>/dev/null | sort -rh
```

---

## 10. NetBox Data as Code

Les données NetBox sont déclarées dans :

`ansible/group_vars/netbox_data.yml`

Le rôle Ansible `netbox_seed` lit ce fichier et crée/met à jour les objets NetBox via l'API :

* régions
* sites Proxmox DC1/DC2
* préfixes LAN, DMZ, WAN et VPN
* rôles, constructeurs, types et plateformes
* équipements pfSense et hôtes Proxmox
* interfaces virtuelles pfSense `WAN`, `LAN`, `DMZ`, `VPN`
* machines virtuelles applicatives
* adresses IP, dont les IP pfSense attachées aux interfaces
* services
* tunnel VPN site-to-site

Les VLANs ne sont plus modélisés dans ce dépôt. Les réseaux sont décrits par les prefixes IP, et les points d'attachement réseau pfSense par des interfaces virtuelles.

Exécution du seed seul :

```bash
ansible-playbook -i ansible/inventory.ini ansible/playbook.yml -k -K --tags netbox_seed
```

---

## 11. pfSense et VPN

Le playbook pfSense est :

```text
ansible/pfsense-playbook.yml
```

Il configure le tunnel OpenVPN site-to-site via `pfsensible.core`.

Les secrets pfSense sont fournis par Vault :

* `vault_pfsense_admin_password`
* `vault_openvpn_static_key`

Installation des collections :

```bash
ansible-galaxy collection install -r requirements.yml
```

Vérification syntaxe :

```bash
ansible-playbook -i ansible/inventory.ini ansible/pfsense-playbook.yml --syntax-check
```

Exécution :

```bash
ansible-playbook -i ansible/inventory.ini ansible/pfsense-playbook.yml
```

---

## 12. Commandes de reconstruction complète

Sur une VM vierge :

```bash
./bootstrap-bastion.sh
ansible-galaxy collection install -r requirements.yml
ansible-playbook -i ansible/inventory.ini ansible/playbook.yml -k -K
```

Résultat attendu :

* NetBox opérationnel
* admin opérationnel
* token API disponible pour le seed Ansible
* référentiel infra injecté

---

## 13. Règles de gouvernance retenues

* éviter les créations manuelles dans l'UI
* toute modification structurelle passe par YAML/Ansible
* aucun secret en clair dans les fichiers du projet
* la UI sert principalement de consultation et contrôle
* relancer les playbooks doit toujours être possible sans destruction

---

## 14. Prochaines extensions prévues

* sync Proxmox API
* sync pfSense/VPN inventory
* génération cartographie automatique hybride


## 14. Accéder à l'interface web de NetBox
``` bas ssh -L 8081:10.10.0.2:8001 lil4@5.135.202.69
```
