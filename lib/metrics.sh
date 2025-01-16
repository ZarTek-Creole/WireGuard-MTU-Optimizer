#!/bin/bash

# Métriques de performance pour WireGuard MTU Optimizer

# Configuration
METRICS_DIR="/var/lib/wg-mtu-opt/metrics"
CURRENT_METRICS_FILE="${METRICS_DIR}/current_metrics.json"
HISTORY_METRICS_FILE="${METRICS_DIR}/metrics_history.json"
ANALYSIS_FILE="${METRICS_DIR}/performance_analysis.json"

# Initialisation du système de métriques
init_metrics_system() {
    mkdir -p "$METRICS_DIR"
    
    # Création du fichier d'historique s'il n'existe pas
    if [[ ! -f "$HISTORY_METRICS_FILE" ]]; then
        cat << EOF > "$HISTORY_METRICS_FILE"
{
    "version": "1.0",
    "last_update": "$(date -Iseconds)",
    "metrics_records": []
}
EOF
    fi
}

# Collecte des métriques actuelles
collect_current_metrics() {
    local interface=$1
    local duration=${2:-10}  # Durée par défaut : 10 secondes
    local server_ip=$3
    
    # Vérification des dépendances
    if ! command -v iperf3 >/dev/null || ! command -v ping >/dev/null; then
        log_error "iperf3 et/ou ping non trouvés"
        return 1
    fi
    
    # Création d'un fichier temporaire pour les résultats
    local temp_dir=$(mktemp -d)
    local iperf_result="${temp_dir}/iperf.json"
    local ping_result="${temp_dir}/ping.txt"
    
    # Test iperf3
    if [[ -n "$server_ip" ]]; then
        iperf3 -c "$server_ip" -J -t "$duration" > "$iperf_result" 2>/dev/null
    fi
    
    # Test ping
    ping -c "$duration" -i 1 -W 1 "$server_ip" > "$ping_result" 2>/dev/null
    
    # Collecte des statistiques système
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | sed 's/%//')
    local memory_usage=$(free | awk '/Mem/{printf("%.2f"), $3/$2*100}')
    local interface_stats=$(ip -s link show "$interface")
    local rx_bytes=$(echo "$interface_stats" | awk '/RX:/{getline; print $1}')
    local tx_bytes=$(echo "$interface_stats" | awk '/TX:/{getline; print $1}')
    
    # Valeurs par défaut si les statistiques sont vides
    rx_bytes=${rx_bytes:-0}
    tx_bytes=${tx_bytes:-0}
    
    # Analyse des résultats
    local latency=$(awk -F'/' '/rtt min/{print $5}' "$ping_result")
    local packet_loss=$(awk -F'%' '/packet loss/{print $1}' "$ping_result" | awk '{print $NF}')
    local jitter=0
    local bandwidth=0
    
    if [[ -f "$iperf_result" ]]; then
        jitter=$(jq -r '.end.sum.jitter_ms' "$iperf_result")
        bandwidth=$(jq -r '.end.sum.bits_per_second' "$iperf_result")
    fi
    
    # Valeurs par défaut si les métriques sont vides
    latency=${latency:-0}
    packet_loss=${packet_loss:-0}
    jitter=${jitter:-0}
    bandwidth=${bandwidth:-0}
    
    # Création du rapport JSON
    local metrics=$(cat << EOF
{
    "timestamp": "$(date -Iseconds)",
    "interface": "$interface",
    "mtu": $(ip link show "$interface" | grep -oP 'mtu \K\d+'),
    "network_metrics": {
        "latency": $latency,
        "jitter": $jitter,
        "packet_loss": $packet_loss,
        "bandwidth": $bandwidth
    },
    "system_metrics": {
        "cpu_usage": $cpu_usage,
        "memory_usage": $memory_usage,
        "interface_stats": {
            "rx_bytes": $rx_bytes,
            "tx_bytes": $tx_bytes
        }
    }
}
EOF
)
    
    # Nettoyage
    rm -rf "$temp_dir"
    
    # Validation du JSON
    if ! echo "$metrics" | jq '.' >/dev/null 2>&1; then
        log_error "JSON invalide généré"
        return 1
    fi
    
    # Sauvegarde des métriques
    echo "$metrics" > "$CURRENT_METRICS_FILE"
    
    # Ajout à l'historique
    if [[ -f "$HISTORY_METRICS_FILE" ]]; then
        if ! jq --arg metrics "$metrics" '.metrics_records += [$metrics | fromjson]' "$HISTORY_METRICS_FILE" > "${HISTORY_METRICS_FILE}.tmp"; then
            log_error "Erreur lors de l'ajout à l'historique"
            return 1
        fi
        mv "${HISTORY_METRICS_FILE}.tmp" "$HISTORY_METRICS_FILE"
    fi
    
    echo "$metrics"
}

# Analyse des performances
analyze_performance() {
    local interface=$1
    local period=${2:-3600}  # Période d'analyse par défaut : 1 heure
    
    # Vérification du fichier d'historique
    if [[ ! -f "$HISTORY_METRICS_FILE" ]]; then
        log_error "Fichier d'historique non trouvé"
        return 1
    fi
    
    # Validation du JSON d'historique
    if ! jq '.' "$HISTORY_METRICS_FILE" >/dev/null 2>&1; then
        log_error "Fichier d'historique JSON invalide"
        return 1
    fi
    
    # Extraction des données récentes
    local since_date=$(date -d "@$(($(date +%s) - period))" -Iseconds)
    local recent_data
    recent_data=$(jq --arg interface "$interface" --arg since "$since_date" \
        '.metrics_records | map(select(.interface == $interface and .timestamp >= $since))' \
        "$HISTORY_METRICS_FILE")
    
    if [[ "$recent_data" == "[]" || -z "$recent_data" ]]; then
        log_warning "Aucune donnée trouvée pour la période spécifiée"
        echo "{}"
        return 0
    fi
    
    # Calcul des statistiques
    local analysis
    analysis=$(jq -n --argjson data "$recent_data" '{
        "period_start": ($data[0].timestamp // null),
        "period_end": ($data[-1].timestamp // null),
        "sample_count": ($data | length),
        "network_stats": {
            "latency": {
                "min": ($data | map(.network_metrics.latency) | min // 0),
                "max": ($data | map(.network_metrics.latency) | max // 0),
                "avg": ($data | map(.network_metrics.latency) | add / length // 0)
            },
            "packet_loss": {
                "min": ($data | map(.network_metrics.packet_loss) | min // 0),
                "max": ($data | map(.network_metrics.packet_loss) | max // 0),
                "avg": ($data | map(.network_metrics.packet_loss) | add / length // 0)
            },
            "bandwidth": {
                "min": ($data | map(.network_metrics.bandwidth) | min // 0),
                "max": ($data | map(.network_metrics.bandwidth) | max // 0),
                "avg": ($data | map(.network_metrics.bandwidth) | add / length // 0)
            }
        },
        "mtu_stats": {
            "changes": ($data | map(.mtu) | unique | length - 1),
            "optimal_range": {
                "min": ($data | map(select(.network_metrics.packet_loss < 1 and .network_metrics.latency < ($data | map(.network_metrics.latency) | add / length * 1.2))) | map(.mtu) | min // 0),
                "max": ($data | map(select(.network_metrics.packet_loss < 1 and .network_metrics.latency < ($data | map(.network_metrics.latency) | add / length * 1.2))) | map(.mtu) | max // 0)
            }
        },
        "system_impact": {
            "cpu_usage": {
                "avg": ($data | map(.system_metrics.cpu_usage) | add / length // 0),
                "max": ($data | map(.system_metrics.cpu_usage) | max // 0)
            },
            "memory_usage": {
                "avg": ($data | map(.system_metrics.memory_usage) | add / length // 0),
                "max": ($data | map(.system_metrics.memory_usage) | max // 0)
            }
        }
    }')
    
    # Validation de l'analyse
    if ! echo "$analysis" | jq '.' >/dev/null 2>&1; then
        log_error "Analyse JSON invalide générée"
        return 1
    fi
    
    # Sauvegarde de l'analyse
    echo "$analysis" > "$ANALYSIS_FILE"
    
    echo "$analysis"
}

# Génération de rapport de performance
generate_performance_report() {
    local interface=$1
    local period=${2:-3600}
    local output_file="${METRICS_DIR}/performance_report_${interface}_$(date +%Y%m%d_%H%M%S).txt"
    
    # Récupération des analyses
    local analysis
    if ! analysis=$(analyze_performance "$interface" "$period"); then
        log_error "Échec de l'analyse des performances"
        return 1
    fi
    
    if [[ "$analysis" == "{}" ]]; then
        log_warning "Aucune donnée à analyser"
        echo "Aucune donnée disponible pour la période spécifiée." > "$output_file"
        echo "$output_file"
        return 0
    fi
    
    # Création du rapport
    {
        echo "Rapport de Performance WireGuard - Interface $interface"
        echo "Période : $(jq -r '.period_start' <<< "$analysis") à $(jq -r '.period_end' <<< "$analysis")"
        echo "Nombre d'échantillons : $(jq -r '.sample_count' <<< "$analysis")"
        echo
        echo "1. Statistiques Réseau"
        echo "   Latence (ms):"
        echo "   - Min: $(jq -r '.network_stats.latency.min' <<< "$analysis")"
        echo "   - Max: $(jq -r '.network_stats.latency.max' <<< "$analysis")"
        echo "   - Moyenne: $(jq -r '.network_stats.latency.avg' <<< "$analysis")"
        echo
        echo "   Perte de paquets (%):"
        echo "   - Min: $(jq -r '.network_stats.packet_loss.min' <<< "$analysis")"
        echo "   - Max: $(jq -r '.network_stats.packet_loss.max' <<< "$analysis")"
        echo "   - Moyenne: $(jq -r '.network_stats.packet_loss.avg' <<< "$analysis")"
        echo
        echo "   Bande passante (bits/s):"
        echo "   - Min: $(jq -r '.network_stats.bandwidth.min' <<< "$analysis")"
        echo "   - Max: $(jq -r '.network_stats.bandwidth.max' <<< "$analysis")"
        echo "   - Moyenne: $(jq -r '.network_stats.bandwidth.avg' <<< "$analysis")"
        echo
        echo "2. Statistiques MTU"
        echo "   Nombre de changements: $(jq -r '.mtu_stats.changes' <<< "$analysis")"
        echo "   Plage optimale:"
        echo "   - Min: $(jq -r '.mtu_stats.optimal_range.min' <<< "$analysis")"
        echo "   - Max: $(jq -r '.mtu_stats.optimal_range.max' <<< "$analysis")"
        echo
        echo "3. Impact Système"
        echo "   CPU (%):"
        echo "   - Moyenne: $(jq -r '.system_impact.cpu_usage.avg' <<< "$analysis")"
        echo "   - Max: $(jq -r '.system_impact.cpu_usage.max' <<< "$analysis")"
        echo
        echo "   Mémoire (%):"
        echo "   - Moyenne: $(jq -r '.system_impact.memory_usage.avg' <<< "$analysis")"
        echo "   - Max: $(jq -r '.system_impact.memory_usage.max' <<< "$analysis")"
    } > "$output_file"
    
    echo "$output_file"
}

# Export des fonctions
export -f init_metrics_system
export -f collect_current_metrics
export -f analyze_performance
export -f generate_performance_report 