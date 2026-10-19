

# DOCUMENTATION TECHNIQUE — SUPERVISION DES LOGS (STACK ELK)

## Projet Cloud — Datacenter 1 & 2

# 1. Présentation de l'architecture

La stack de supervision des logs est composée des outils suivants :

- **Filebeat** : Agent de collecte de logs, installé sur toutes les VM.
- **Elasticsearch** : Moteur de stockage et d'indexation des logs.
- **Kibana** : Interface web de visualisation des logs.

> **Remarque :** Logstash n'a pas été intégré à cette architecture. Filebeat envoie directement les logs à Elasticsearch, sans passer par Logstash.

## Schéma de l'architecture

```text
[VM - Filebeat] ──────────────────► [Elasticsearch (VM1 DC1)]
                                            ▲
                                            │
                                    [Kibana (VM2 DC1)]
```

## Adresses des services

- **Elasticsearch** : `http://10.10.0.2:9200`
- **Kibana** : `http://10.10.0.3:5601`

### Accès

Les services ne sont accessibles que via **VPN** ou via un **bastion SSH** utilisé comme proxy (redirection de port).

**Exemple de redirection via bastion :**

```bash
ssh -L 9200:10.10.0.2:9200 user@bastion
ssh -L 5601:10.10.0.3:5601 user@bastion
```

---

# 2. Installation de Filebeat (sur toutes les VM)

Filebeat est l'agent de collecte de logs. Il doit être installé sur :

- VM1 et VM2 du DC1
- VM1 et VM2 du DC2
- pfSense DC1
- pfSense DC2

L'installation a été automatisée via **Ansible**.

## 2.1 Prérequis : Clé SSH

Une clé SSH a été générée pour permettre la connexion sans mot de passe :

```bash
ssh-keygen -t ed25519 -a 100 -C "ma clé ssh"
```

La clé publique a ensuite été copiée sur toutes les VM cibles.

## 2.2 Déploiement via Ansible

Le déploiement de Filebeat est géré par un playbook Ansible :

```bash
ansible-playbook -i inventory.yml main.yml
```

Le projet Ansible est structuré en rôles, avec un rôle dédié à Filebeat (installation du paquet, configuration et activation du service).

## 2.3 Configuration de Filebeat

Le fichier `/etc/filebeat/filebeat.yml` doit pointer vers Elasticsearch :

```yaml
output.elasticsearch:
  hosts: ["http://10.10.0.2:9200"]
```

Activer le module système (optionnel mais recommandé) :

```bash
filebeat modules enable system
```

Démarrer et activer Filebeat :

```bash
systemctl enable filebeat
systemctl start filebeat
```

Vérifier le statut :

```bash
systemctl status filebeat
```

---

# 3. Installation d'Elasticsearch (VM1 — DC1 — 10.10.0.2)

Elasticsearch est le moteur central de stockage et d'indexation des logs.

## 3.1 Installation

```bash
wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch \
| sudo gpg --dearmor -o /usr/share/keyrings/elasticsearch-keyring.gpg

echo "deb [signed-by=/usr/share/keyrings/elasticsearch-keyring.gpg] \
https://artifacts.elastic.co/packages/8.x/apt stable main" \
| sudo tee /etc/apt/sources.list.d/elastic-8.x.list

sudo apt update && sudo apt install elasticsearch -y
```

## 3.2 Configuration (`/etc/elasticsearch/elasticsearch.yml`)

```yaml
network.host: 0.0.0.0
http.port: 9200
discovery.type: single-node
xpack.security.enabled: false
```

## 3.3 Démarrage

```bash
systemctl enable elasticsearch
systemctl start elasticsearch
```

Vérification :

```bash
curl http://10.10.0.2:9200
```

**Réponse attendue :** un objet JSON contenant notamment le nom du nœud et la version d'Elasticsearch.

## 3.4 Point d'attention : espace disque

> ⚠️ **Problème identifié :** Au démarrage d'Elasticsearch, l'utilisation du disque atteint environ **98 %**. Il est recommandé de surveiller l'espace disponible et d'envisager une extension du stockage avant la mise en production.

Commande de vérification :

```bash
df -h
```

---

# 4. Installation de Kibana (VM2 — DC1 — 10.10.0.3)

Kibana est l'interface web permettant de visualiser et d'interroger les logs stockés dans Elasticsearch.

## 4.1 Installation

```bash
sudo apt update && sudo apt install kibana -y
```

## 4.2 Configuration (`/etc/kibana/kibana.yml`)

```yaml
server.port: 5601
server.host: "0.0.0.0"
elasticsearch.hosts:
  - "http://10.10.0.2:9200"
```

## 4.3 Démarrage

```bash
systemctl enable kibana
systemctl start kibana
```

Vérification : ouvrir `http://10.10.0.3:5601` dans un navigateur (via VPN ou redirection SSH).

---

# 5. Chronologie des travaux

## Janvier 2026

- Installation de Filebeat sur :
  - pfSense DC1
  - pfSense DC2
  - VM1 et VM2 du DC1
  - VM1 et VM2 du DC2

## Février – Mars 2026

- Installation initiale d'Elasticsearch et Kibana.
- Configuration initiale d'Elasticsearch.
- Stack ELK partiellement fonctionnelle.
- Étape suivante identifiée : configurer Filebeat pour pointer vers Elasticsearch (`10.10.0.3:9200` à l'époque).

## Avril – Mai 2026

- Suppression d'Elasticsearch de la VM2 (`10.10.0.3`).
- Conservation de Kibana sur la VM2 (`10.10.0.3`).

## Avril – Mai 2026

- Génération d'une clé SSH **ed25519**.
- Copie de la clé sur toutes les VM.
- Mise en place de playbooks et rôles Ansible pour automatiser :
  - Elasticsearch
  - Kibana
  - Filebeat
- Identification d'un problème d'espace disque (98 % au démarrage).
- Configuration Filebeat/Kibana vers Elasticsearch restant à finaliser.

## Juin 2026

Installation finalisée :

- **Filebeat** → toutes les VM.
- **Elasticsearch** → VM1 DC1 (`10.10.0.2:9200`).
- **Kibana** → VM2 DC1 (`10.10.0.3:5601`).

Architecture opérationnelle :

```text
Filebeat ──► Elasticsearch ◄── Kibana
```

---

# 6. Points en suspens / Prochaines étapes

- ⚠️ Surveiller et étendre le stockage (98 % au démarrage).
- ⚠️ Vérifier la communication **Filebeat → Elasticsearch** sur toutes les VM.
- ⚠️ Vérifier que Kibana affiche correctement les index Filebeat.
- ☐ Créer les **index patterns** `filebeat-*` dans Kibana.
- ☐ Configurer des tableaux de bord (dashboards) de supervision dans Kibana.
- ☐ Envisager l'ajout de **Logstash** si des transformations de logs deviennent nécessaires.

---

# Important : la redondance

La redondance constitue un élément essentiel de ce projet, car elle garantit la continuité des services en cas de défaillance d’un composant. En mettant en place des mécanismes de duplication des ressources critiques (serveurs, services ou configurations), il est possible de limiter les interruptions et d’assurer une meilleure disponibilité de l’infrastructure.

Dans le cadre de ce projet, la redondance contribue également à améliorer la fiabilité et la résilience du système. Si une instance d’Elasticsearch ou un autre composant devient indisponible, une autre peut prendre le relais afin de maintenir le fonctionnement des applications et l’accès aux données. Cette approche réduit le risque de **Single Point of Failure (SPOF)** et facilite les opérations de maintenance sans interruption majeure du service.

Enfin, intégrer la redondance dès la conception permet de construire une infrastructure plus robuste, capable de répondre aux exigences de disponibilité et de performance attendues dans un environnement professionnel. Elle s’inscrit donc comme un principe fondamental pour assurer la pérennité et la stabilité du projet.
