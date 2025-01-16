# WireGuard MTU Optimizer (WG-MTU-OPT)

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Bash](https://img.shields.io/badge/Language-Bash-green.svg)](https://www.gnu.org/software/bash/)
[![WireGuard](https://img.shields.io/badge/Network-WireGuard-88171A.svg)](https://www.wireguard.com/)

## Description

WireGuard MTU Optimizer est un outil sophistiqué d'optimisation réseau qui automatise la découverte et l'ajustement des paramètres MTU pour les interfaces WireGuard. Le script utilise des techniques avancées de test parallèle et d'analyse de performance pour déterminer la configuration optimale.

## Caractéristiques

### Optimisation Intelligente
- 🔍 Détection automatique des interfaces WireGuard
- 📊 Tests MTU parallèles avec logique de retry intelligente
- 📈 Analyse complète des performances (latence & débit)
- 🔄 Optimisation auto-adaptative basée sur les métriques

### Monitoring Avancé
- 📉 Surveillance continue des performances
- 🚨 Détection proactive des anomalies
- 📊 Analyse des tendances en temps réel
- 💡 Recommandations d'optimisation automatiques

### Sécurité et Fiabilité
- 🔒 Gestion sécurisée des configurations
- 💾 Sauvegarde automatique avec métadonnées
- ✅ Validation approfondie des paramètres
- 🔄 Restauration automatique en cas d'erreur

### Rapports et Analyses
- 📋 Logs détaillés et rotation automatique
- 📊 Graphiques de performance
- 📈 Analyse statistique des métriques
- 📑 Rapports d'optimisation complets

## Prérequis

- Interface WireGuard configurée
- iperf3 pour les tests de performance
- parallel pour les tests parallèles
- bash 4.0+
- Privilèges root

## Installation

```bash
git clone https://github.com/ZarTek-Creole/WireGuard-MTU-Optimizer.git
cd WireGuard-MTU-Optimizer
chmod +x wireguard-mtu-tune.sh
```

## Utilisation

### Mode Standard
```bash
sudo ./wireguard-mtu-tune.sh -i wg0
```

### Mode Avancé
```bash
sudo ./wireguard-mtu-tune.sh -i wg0 -s 10.0.0.1 -m 1280 -n 1500 -p 10 -v -r 3
```

### Options
- `-i INTERFACE` : Interface WireGuard (auto-détection par défaut)
- `-s SERVER_IP` : IP du serveur de test (défaut: 10.66.66.1)
- `-m MIN_MTU` : MTU minimum (défaut: 1280)
- `-n MAX_MTU` : MTU maximum (défaut: 1500)
- `-p STEP` : Incrément MTU (défaut: 10)
- `-l LOG_FILE` : Fichier de log (défaut: /tmp/mtu_test.log)
- `-j MAX_JOBS` : Nombre de jobs parallèles (défaut: nproc)
- `-v` : Mode verbeux
- `-r RETRY_COUNT` : Nombre de tentatives (défaut: 3)

## Monitoring et Optimisation Continue

### Surveillance des Performances
```bash
# Démarrer la surveillance continue
sudo ./wireguard-mtu-tune.sh -i wg0 --monitor

# Afficher les tendances de performance
sudo ./wireguard-mtu-tune.sh -i wg0 --show-trends

# Générer un rapport d'optimisation
sudo ./wireguard-mtu-tune.sh -i wg0 --generate-report
```

### Optimisation Auto-adaptative
```bash
# Activer l'optimisation auto-adaptative
sudo ./wireguard-mtu-tune.sh -i wg0 --auto-adapt

# Définir les seuils d'optimisation
sudo ./wireguard-mtu-tune.sh -i wg0 --set-thresholds "latency=100,loss=5,jitter=20"
```

## Exemple de Sortie

```plaintext
[2024-01-20 15:30:45] [LOG_INFO] Démarrage de l'optimisation MTU pour wg0
[2024-01-20 15:30:46] [LOG_INFO] Configuration système validée
[2024-01-20 15:30:47] [LOG_INFO] Démarrage des tests parallèles
[2024-01-20 15:31:15] [LOG_INFO] Analyse des résultats
[2024-01-20 15:31:16] [LOG_INFO] MTU optimal trouvé : 1420
[2024-01-20 15:31:17] [LOG_INFO] Application de la configuration optimale
[2024-01-20 15:31:18] [LOG_INFO] Optimisation terminée avec succès
```

## Graphiques de Performance

![Performance MTU](docs/images/mtu_performance.png)

## Tests

```bash
# Exécuter les tests unitaires
./tests/run_tests.sh

# Exécuter les tests de performance
./tests/performance_tests.sh
```

## Contribution

Les contributions sont les bienvenues ! Consultez [CONTRIBUTING.md](CONTRIBUTING.md) pour les directives.

## Licence

Ce projet est sous licence MIT. Voir le fichier [LICENSE](LICENSE) pour plus de détails.

## Auteur

**ZarTek-Creole**
- GitHub: [@ZarTek-Creole](https://github.com/ZarTek-Creole)
- Blog: [Blog personnel](https://zartek-creole.github.io)

## Tags

`#wireguard` `#networking` `#optimization` `#linux` `#security` `#performance` `#monitoring` `#automation` `#bash` `#devops`
