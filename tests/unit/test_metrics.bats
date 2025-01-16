#!/usr/bin/env bats

load '../test_helper'
load '../../lib/metrics.sh'

# Configuration pour les tests
setup() {
    export TEMP_DIR=$(mktemp -d)
    export METRICS_DIR="${TEMP_DIR}/metrics"
    export CURRENT_METRICS_FILE="${METRICS_DIR}/current_metrics.json"
    export HISTORY_METRICS_FILE="${METRICS_DIR}/metrics_history.json"
    export ANALYSIS_FILE="${METRICS_DIR}/performance_analysis.json"
    
    mkdir -p "$METRICS_DIR"
    
    # Fonctions de logging simulées
    log_error() { echo "ERROR: $1" >&2; }
    log_warning() { echo "WARNING: $1" >&2; }
    log_info() { echo "INFO: $1" >&2; }
    
    export -f log_error
    export -f log_warning
    export -f log_info
}

# Test d'initialisation
@test "Metrics - Initialisation du système" {
    run init_metrics_system
    [ "$status" -eq 0 ]
    [ -f "$HISTORY_METRICS_FILE" ]
    
    # Vérification de la structure JSON
    run jq '.' "$HISTORY_METRICS_FILE"
    [ "$status" -eq 0 ]
}

# Test de collecte des métriques
@test "Metrics - Collecte des métriques actuelles" {
    local interface="wg0"
    local server_ip="1.2.3.4"  # IP fictive pour le test
    
    # Création des fonctions simulées
    function iperf3() {
        echo '{"end":{"sum":{"jitter_ms":2.1,"bits_per_second":100000000}}}'
    }
    
    function ip() {
        echo "Command: ip $*" >&2
        if [[ "$*" =~ "link show" ]]; then
            echo "mtu 1420"
        elif [[ "$*" =~ "-s link show" ]]; then
            echo "RX: bytes"
            echo "1000"
            echo "TX: bytes"
            echo "1000"
        fi
    }
    
    function top() {
        echo "Cpu(s): 10.5%"
    }
    
    function free() {
        echo "Mem: 16384 8192 8192"
    }
    
    function ping() {
        echo "rtt min/avg/max/mdev = 10.2/15.3/20.4/5.1 ms"
        echo "1 packets transmitted, 1 received, 0% packet loss"
    }
    
    export -f iperf3
    export -f ip
    export -f top
    export -f free
    export -f ping
    
    # Initialisation du système de métriques
    init_metrics_system
    
    # Test de la collecte
    run collect_current_metrics "$interface" 1 "$server_ip"
    echo "Status: $status" >&2
    echo "Output: $output" >&2
    [ "$status" -eq 0 ]
    
    # Vérification des métriques
    [ -f "$CURRENT_METRICS_FILE" ]
    echo "Current metrics file content:" >&2
    cat "$CURRENT_METRICS_FILE" >&2
    
    run jq -r '.interface' "$CURRENT_METRICS_FILE"
    echo "Interface output: $output" >&2
    [ "$output" = "$interface" ]
    
    run jq -r '.mtu' "$CURRENT_METRICS_FILE"
    echo "MTU output: $output" >&2
    [ "$output" = "1420" ]
}

# Test d'analyse des performances
@test "Metrics - Analyse des performances" {
    local interface="wg0"
    
    # Initialisation du système de métriques
    init_metrics_system
    
    # Création de données historiques
    cat << EOF > "$HISTORY_METRICS_FILE"
{
    "version": "1.0",
    "last_update": "$(date -Iseconds)",
    "metrics_records": [
        {
            "timestamp": "$(date -Iseconds)",
            "interface": "wg0",
            "mtu": 1420,
            "network_metrics": {
                "latency": 15.3,
                "jitter": 2.1,
                "packet_loss": 0.1,
                "bandwidth": 100000000
            },
            "system_metrics": {
                "cpu_usage": 10.5,
                "memory_usage": 50.0,
                "interface_stats": {
                    "rx_bytes": 1000,
                    "tx_bytes": 1000
                }
            }
        }
    ]
}
EOF
    
    echo "History file content:" >&2
    cat "$HISTORY_METRICS_FILE" >&2
    
    run analyze_performance "$interface" 60
    echo "Status: $status" >&2
    echo "Output: $output" >&2
    [ "$status" -eq 0 ]
    
    # Vérification de l'analyse
    [ -f "$ANALYSIS_FILE" ]
    echo "Analysis file content:" >&2
    cat "$ANALYSIS_FILE" >&2
    
    # Vérification du nombre d'échantillons
    run jq -r '.sample_count' <<< "$output"
    echo "Sample count output: $output" >&2
    [ "$output" = "1" ]
}

# Test de génération de rapport
@test "Metrics - Génération de rapport de performance" {
    local interface="wg0"
    
    # Initialisation du système de métriques
    init_metrics_system
    
    # Création de données historiques
    cat << EOF > "$HISTORY_METRICS_FILE"
{
    "version": "1.0",
    "last_update": "$(date -Iseconds)",
    "metrics_records": [
        {
            "timestamp": "$(date -Iseconds)",
            "interface": "wg0",
            "mtu": 1420,
            "network_metrics": {
                "latency": 15.3,
                "jitter": 2.1,
                "packet_loss": 0.1,
                "bandwidth": 100000000
            },
            "system_metrics": {
                "cpu_usage": 10.5,
                "memory_usage": 50.0,
                "interface_stats": {
                    "rx_bytes": 1000,
                    "tx_bytes": 1000
                }
            }
        }
    ]
}
EOF
    
    echo "History file content:" >&2
    cat "$HISTORY_METRICS_FILE" >&2
    
    run generate_performance_report "$interface" 60
    echo "Status: $status" >&2
    echo "Output: $output" >&2
    [ "$status" -eq 0 ]
    
    # Vérification du rapport
    [ -f "$output" ]
    echo "Report file content:" >&2
    cat "$output" >&2
    
    # Vérification du contenu
    run cat "$output"
    [[ "$output" =~ "Rapport de Performance WireGuard" ]]
    [[ "$output" =~ "Statistiques Réseau" ]]
    [[ "$output" =~ "Statistiques MTU" ]]
    [[ "$output" =~ "Impact Système" ]]
}

# Nettoyage
teardown() {
    if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
    fi
} 