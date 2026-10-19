

# Définition du plan d’adressage
```aiignore
Site 1(DC1)
- LAN: 10.10.0.0/24
- DMZ: 10.10.10.0/24
- pfSense LAN: 10.10.0.1
- pfSense DMZ: 10.10.10.1
- NetBox/DNS: 10.10.0.10
- Elasticsearch: 10.10.0.20

Site 2(DC2)
- LAN: 10.20.0.0/24
- DMZ: 10.20.10.0/24
- pfSense LAN: 10.20.0.1
- pfSense DMZ: 10.20.10.1
- Web interne: 10.20.0.10
- Bastion: 10.20.10.10

VPN
- Transit: 10.255.255.0/30
- pfSense S1 VPN: 10.255.255.1
- pfSense S2 VPN: 10.255.255.2
```

### Static address ip config
> Site 1
>
> - **Lan address**: 10.10.0.1/24
> - **VM1 address**: 10.10.0.2
> - **VM2-address**: 10.10.0.3
> - **WAN address**: 51.254.7.156/24
> - **Gateway**: 51.254.7.254 

> Site 2 
> 
> - **Lan address**:  10.20.0.1/24
> - **WAN address**: 5.135.202.69/24
> - **VM1 address**: 10.20.0.3
> - **VM2-address**: 10.20.0.2
> - **DMZ address**: 10.20.10.1/24
### OpenVPN config
The whole documentation is found [here](https://wiki.debian.org/OpenVPN)
### PFPSense Tools
Documentation [here](https://docs.netgate.com/pfsense/en/latest/development/php-shell.html)



# Vérifier Ansible
ansible --version

# Test de connectivité vers les deux VMs
ansible all -i ~/kill-switch/ansible/inventory.ini -m ping

## Gestion d'Ansible Vault (Chiffrement / Déchiffrement)

Tous les secrets et mots de passe du projet sont chiffrés à l'aide d'Ansible Vault et partagent la même clé secrète stockée dans `netbox-iac/ansible/.vault-pass`.

Les configurations `ansible.cfg` des différents projets (`netbox-iac`, `dns-dhcp-iac`, `web-iac`, `kill-switch2`) chargent cette clé automatiquement lors de l'exécution des playbooks.

### 1. Consulter un fichier chiffré en clair
Pour afficher le contenu d'un fichier coffre-fort (ex: `vault.yml`) sans le déchiffrer sur le disque :
```bash
ansible-vault view --vault-password-file netbox-iac/ansible/.vault-pass <chemin_du_fichier_vault.yml>
```
*Exemple :*
```bash
ansible-vault view --vault-password-file netbox-iac/ansible/.vault-pass dns-dhcp-iac/ansible/group_vars/all/vault.yml
```

### 2. Déchiffrer un fichier (passage en clair sur le disque)
Pour repasser un fichier chiffré en clair afin de le modifier :
```bash
ansible-vault decrypt --vault-password-file netbox-iac/ansible/.vault-pass <chemin_du_fichier_vault.yml>
```

### 3. Re-chiffrer un fichier
Pour chiffrer à nouveau un fichier qui a été passé en clair :
```bash
ansible-vault encrypt --vault-password-file netbox-iac/ansible/.vault-pass <chemin_du_fichier_vault.yml>
```

### 4. Modifier directement un fichier chiffré (via l'éditeur CLI)
Pour éditer directement un fichier chiffré de manière transparente :
```bash
ansible-vault edit --vault-password-file netbox-iac/ansible/.vault-pass <chemin_du_fichier_vault.yml>
```
