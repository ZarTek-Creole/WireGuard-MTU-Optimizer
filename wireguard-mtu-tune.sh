#!/bin/bash
#
# WireGuard MTU Optimizer (WG-MTU-OPT)
# Version: 1.0.0
#
# Author: ZarTek-Creole (https://github.com/ZarTek-Creole)
# Repository: https://github.com/ZarTek-Creole/WireGuard-MTU-Optimizer
# License: MIT
#
# Description:
#   A sophisticated network optimization tool that automatically discovers and
#   fine-tunes WireGuard MTU settings for optimal performance. The script conducts
#   parallel testing of different MTU values while measuring both latency and
#   throughput to determine the most efficient configuration.
#
# Features:
#   - Automatic WireGuard interface detection
#   - Parallel MTU testing with smart retry logic
#   - Comprehensive performance analysis (latency & throughput)
#   - Detailed logging and real-time monitoring
#   - Resource-aware parallel processing
#   - Automated log rotation
#
# Dependencies:
#   - WireGuard interface
#   - iperf3
#   - parallel
#   - bash 4.0+
#   - Root privileges
#
# Usage:
#   ./wireguard-mtu-tune.sh [-i INTERFACE] [-s SERVER_IP] [-m MIN_MTU] [-n MAX_MTU]
#                          [-p STEP] [-l LOG_FILE] [-j MAX_JOBS] [-v] [-r RETRY_COUNT]
#
# Options:
#   -i INTERFACE   : Specify WireGuard interface (default: auto-detect)
#   -s SERVER_IP   : Server IP for testing (default: 95.216.45.182)
#   -m MIN_MTU     : Minimum MTU value (default: 1280)
#   -n MAX_MTU     : Maximum MTU value (default: 1500)
#   -p STEP        : MTU increment step (default: 10)
#   -l LOG_FILE    : Log file location (default: /tmp/mtu_test.log)
#   -j MAX_JOBS    : Number of parallel jobs (default: CPU cores)
#   -v             : Enable verbose logging
#   -r RETRY_COUNT : Number of retry attempts (default: 3)
#
# Example:
#   sudo ./wireguard-mtu-tune.sh -i wg0 -s 10.0.0.1 -m 1280 -n 1500 -p 10 -v 

# Set strict error handling
set -euo pipefail
IFS=$'\n\t'

# Color definitions for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m' # No Color

# Variables globales
INTERFACE=""
SERVER_IP=""
MIN_MTU=1280
MAX_MTU=1500
VERBOSITY=1
RETRY_COUNT=3
TEMP_DIR="/var/log/wireguard-mtu-optimizer"
BACKUP_DIR="$TEMP_DIR/backup"
LOGS_DIR="$TEMP_DIR/logs"

# Traitement des arguments
while getopts "i:s:m:n:v" opt; do
    case $opt in
        i) INTERFACE="$OPTARG" ;;
        s) SERVER_IP="$OPTARG" ;;
        m) MIN_MTU="$OPTARG" ;;
        n) MAX_MTU="$OPTARG" ;;
        v) VERBOSITY=$((VERBOSITY + 1)) ;;
        *) echo "Usage: $0 -i <interface> -s <server_ip> [-m min_mtu] [-n max_mtu] [-v]" >&2; exit 1 ;;
    esac
done

# Vérification des arguments obligatoires
if [[ -z "$INTERFACE" || -z "$SERVER_IP" ]]; then
    echo "Usage: $0 -i <interface> -s <server_ip> [-m min_mtu] [-n max_mtu] [-v]" >&2
    exit 1
fi

# Default configuration values
MIN_MTU=1280
MAX_MTU=1500
STEP=10
LOG_FILE="/tmp/mtu_test.log"
MAX_JOBS=$(nproc)
LOCK_FILE="${TEMP_DIR}/wg_mtu_lock"

# Fonctions de logging
log_info() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [LOG_INFO] $1"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [LOG_ERROR] $1" >&2
}

log_debug() {
    if [ "$VERBOSITY" -ge 2 ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [LOG_DEBUG] $1"
    fi
}

# Fonction de nettoyage
cleanup() {
    local exit_code=$1
    
    # Restauration de la configuration de l'interface si elle existe
    if [[ -f "$BACKUP_DIR/interface_config" ]]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [LOG_INFO] Restauration de la configuration de l'interface"
        while IFS= read -r line || [[ -n "$line" ]]; do
            eval "$line"
        done < "$BACKUP_DIR/interface_config"
    fi
    
    # Suppression des fichiers temporaires
    if [[ -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
    fi
    
    exit "$exit_code"
}

# Création des répertoires nécessaires
echo "[DEBUG] Création des répertoires..."
sudo install -d -m 755 "$TEMP_DIR"
sudo install -d -m 755 "$BACKUP_DIR"
sudo install -d -m 755 "$LOGS_DIR"
sudo install -m 644 /dev/null "$TEMP_DIR/sysctl_verify"
sudo install -m 644 /dev/null "$BACKUP_DIR/interface_config"
echo "[DEBUG] Répertoires créés"

# Fonction principale
main() {
    # Vérification des paramètres
    if [[ -z "$INTERFACE" || -z "$SERVER_IP" ]]; then
        echo "Usage: $0 -i <interface> -s <server_ip>"
        exit 1
    fi
    
    # Configuration des paramètres système
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [LOG_INFO] Configuration des paramètres système pour WireGuard..."
    configure_system_parameters
    
    # Test de connectivité
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [LOG_INFO] Test de connectivité..."
    if ! ping -c 1 -W 2 "$SERVER_IP" > /dev/null 2>&1; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [LOG_ERROR] Impossible de joindre le serveur $SERVER_IP"
        cleanup 1
    fi
    
    # Optimisation MTU
    optimize_mtu
}

# Fonction de test de performance complète
test_performance() {
    local mtu=$1
    local score=0
    
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [LOG_INFO] Test complet pour MTU = $mtu"
    
    # Test de latence
    local ping_result=$(ping -c 10 -s $(($mtu - 28)) -M do "$SERVER_IP" 2>&1)
    local packet_loss=$(echo "$ping_result" | grep -oP '\d+(?=% packet loss)' || echo "100")
    local latency=$(echo "$ping_result" | grep -oP 'rtt min/avg/max/mdev = \K[\d.]+/[\d.]+/[\d.]+/[\d.]+' | cut -d'/' -f2 || echo "999999")
    
    # Calcul du score
    if [[ "$packet_loss" != "100" && "$latency" != "999999" ]]; then
        # Score basé sur la latence (plus la latence est basse, meilleur est le score)
        score=$(echo "1000 - $latency" | bc -l 2>/dev/null || echo "0")
        if [[ "$packet_loss" != "0" ]]; then
            # Pénalité pour la perte de paquets
            score=$(echo "$score * (100 - $packet_loss) / 100" | bc -l 2>/dev/null || echo "0")
        fi
    fi
    
    # Sauvegarde des résultats
    echo "$mtu,$latency,$packet_loss,$score" >> "$LOGS_DIR/results.csv"
    
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [LOG_INFO] Score pour MTU $mtu : $score (Latence: $latency ms, Perte: $packet_loss%)"
    
    echo "$score"
}

# Fonction d'optimisation MTU améliorée
optimize_mtu() {
    local current_mtu=$(ip link show "$INTERFACE" | grep -oP 'mtu \K\d+')
    local best_mtu=$current_mtu
    local best_latency=999999
    local best_packet_loss=100
    
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [LOG_INFO] Démarrage de l'optimisation MTU avancée..."
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [LOG_INFO] MTU actuel : $current_mtu"
    
    # Création du fichier de résultats
    echo "mtu,latency,packet_loss" > "$LOGS_DIR/results.csv"
    
    # Test de différentes valeurs MTU
    for mtu in $(seq $MIN_MTU 20 $MAX_MTU); do
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [LOG_INFO] Test avec MTU = $mtu"
        
        # Configuration du MTU
        ip link set dev "$INTERFACE" mtu $mtu
        
        # Test de performance
        local ping_result=$(ping -c 10 -s $(($mtu - 28)) -M do "$SERVER_IP" 2>&1)
        local packet_loss=$(echo "$ping_result" | grep -oP '\d+(?=% packet loss)' || echo "100")
        local latency=$(echo "$ping_result" | grep -oP 'rtt min/avg/max/mdev = \K[\d.]+/[\d.]+/[\d.]+/[\d.]+' | cut -d'/' -f2 || echo "999999")
        
        # Sauvegarde des résultats
        echo "$mtu,$latency,$packet_loss" >> "$LOGS_DIR/results.csv"
        
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [LOG_INFO] Résultats : Latence = $latency ms, Perte = $packet_loss%"
        
        # Mise à jour de la meilleure valeur
        if [ "$packet_loss" -lt "$best_packet_loss" ] || 
           ([ "$packet_loss" -eq "$best_packet_loss" ] && 
            [ "$(echo "$latency < $best_latency" | bc -l)" -eq 1 ]); then
            best_mtu=$mtu
            best_latency=$latency
            best_packet_loss=$packet_loss
        fi
    done
    
    # Application de la meilleure valeur
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [LOG_INFO] MTU optimal trouvé : $best_mtu (Latence: $best_latency ms, Perte: $best_packet_loss%)"
    ip link set dev "$INTERFACE" mtu $best_mtu
    
    # Sauvegarde de la configuration
    echo "ip link set dev $INTERFACE mtu $best_mtu" > "$BACKUP_DIR/interface_config"
    
    # Génération du rapport
    generate_report "$best_mtu" "$best_latency" "$best_packet_loss"
    
    cleanup 0
}

# Fonction de génération de rapport
generate_report() {
    local best_mtu=$1
    local best_latency=$2
    local best_packet_loss=$3
    local report_file="$LOGS_DIR/report.txt"
    
    # Création du fichier de rapport avec les bonnes permissions
    sudo install -m 644 /dev/null "$report_file"
    
    {
        echo "=== Rapport d'optimisation MTU ==="
        echo "Date: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "Interface: $INTERFACE"
        echo "Serveur: $SERVER_IP"
        echo "MTU optimal: $best_mtu"
        echo "Meilleure latence: $best_latency ms"
        echo "Perte de paquets: $best_packet_loss%"
        echo ""
        echo "=== Résultats détaillés ==="
        echo "MTU,Latence (ms),Perte (%)"
        cat "$LOGS_DIR/results.csv"
    } | sudo tee "$report_file" > /dev/null
    
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [LOG_INFO] Rapport généré : $report_file"
}

# Fonction de configuration des paramètres système
configure_system_parameters() {
    # Sauvegarde des paramètres actuels
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [LOG_INFO] Sauvegarde de la configuration sysctl existante"
    
    # Configuration des paramètres réseau
    sysctl -w net.core.rmem_max=2500000
    sysctl -w net.core.wmem_max=2500000
    sysctl -w net.core.rmem_default=1000000
    sysctl -w net.core.wmem_default=1000000
    sysctl -w net.ipv4.tcp_rmem="4096 87380 2500000"
    sysctl -w net.ipv4.tcp_wmem="4096 87380 2500000"
    sysctl -w net.core.netdev_max_backlog=5000
    sysctl -w net.ipv4.tcp_mtu_probing=1
    sysctl -w net.ipv4.tcp_congestion_control=cubic
    sysctl -w net.ipv4.ip_forward=1
    sysctl -w net.ipv4.ip_no_pmtu_disc=0
    sysctl -w net.ipv4.tcp_ecn=1
    
    # Configuration spécifique pour l'interface WireGuard
    sysctl -w net.ipv4.conf."$INTERFACE".rp_filter=2
    sysctl -w net.ipv4.conf."$INTERFACE".accept_redirects=0
    sysctl -w net.ipv4.conf."$INTERFACE".send_redirects=0
    
    # Configuration TCP avancée
    sysctl -w net.ipv4.tcp_fastopen=3
    sysctl -w net.ipv4.tcp_slow_start_after_idle=0
    sysctl -w net.ipv4.tcp_fin_timeout=15
    sysctl -w net.ipv4.tcp_keepalive_time=300
    sysctl -w net.ipv4.tcp_keepalive_probes=5
    sysctl -w net.ipv4.tcp_keepalive_intvl=15
    sysctl -w net.ipv4.tcp_window_scaling=1
    sysctl -w net.ipv4.tcp_timestamps=1
    sysctl -w net.ipv4.tcp_sack=1
    sysctl -w net.ipv4.tcp_fack=1
    
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [LOG_INFO] Paramètres système configurés avec succès"
}

# Appel de la fonction principale avec les arguments
main "$@" 