#!/usr/bin/env bats

load '../../wireguard-mtu-tune.sh'

# Tests de surveillance des performances
@test "Surveillance des performances - Création du fichier de stats" {
    local interface="wg0"
    local temp_dir=$(mktemp -d)
    TEMP_DIR="$temp_dir"
    
    run monitor_performance "$interface"
    
    [ -f "${TEMP_DIR}/performance_stats" ]
    [ -f "${TEMP_DIR}/performance_analysis" ]
}

@test "Analyse des données de performance" {
    local temp_dir=$(mktemp -d)
    TEMP_DIR="$temp_dir"
    local stats_file="${TEMP_DIR}/performance_stats"
    
    # Création de données de test
    cat << EOF > "$stats_file"
timestamp,latency,throughput,packet_loss,jitter,tcp_window
1623456789,50.2,100.5,0.1,2.3,65535
1623456790,48.5,102.3,0.0,2.1,65535
1623456791,51.3,99.8,0.2,2.4,65535
EOF
    
    run analyze_performance_data "$stats_file"
    
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Performance Analysis Summary" ]]
}

@test "Détection des anomalies de performance" {
    local temp_dir=$(mktemp -d)
    TEMP_DIR="$temp_dir"
    local stats_file="${TEMP_DIR}/performance_stats"
    
    # Création de données de test avec anomalies
    cat << EOF > "$stats_file"
timestamp,latency,throughput,packet_loss,jitter,tcp_window
1623456789,150.2,100.5,6.1,25.3,65535
EOF
    
    run detect_performance_anomalies "$stats_file"
    
    [ "$status" -eq 0 ]
    [[ "$output" =~ "High latency detected" ]]
    [[ "$output" =~ "High packet loss detected" ]]
    [[ "$output" =~ "High jitter detected" ]]
}

@test "Optimisation auto-adaptative - Ajustement MTU" {
    local interface="wg0"
    local temp_dir=$(mktemp -d)
    TEMP_DIR="$temp_dir"
    local stats_file="${TEMP_DIR}/performance_stats"
    
    # Simulation de métriques nécessitant un ajustement
    cat << EOF > "$stats_file"
timestamp,latency,throughput,packet_loss,jitter,tcp_window
1623456789,120.5,95.2,2.5,16.3,65535
EOF
    
    run auto_adapt_parameters "$interface"
    
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Ajustement auto-adaptatif du MTU" ]]
}

@test "Collecte des métriques actuelles" {
    local interface="wg0"
    local temp_dir=$(mktemp -d)
    TEMP_DIR="$temp_dir"
    
    run collect_current_metrics "$interface"
    
    [ "$status" -eq 0 ]
    [ -f "$output" ]
    [[ $(cat "$output") =~ "timestamp=" ]]
    [[ $(cat "$output") =~ "latency=" ]]
    [[ $(cat "$output") =~ "packet_loss=" ]]
}

@test "Analyse des tendances de performance" {
    local temp_dir=$(mktemp -d)
    TEMP_DIR="$temp_dir"
    local metrics_file="${TEMP_DIR}/current_metrics"
    
    # Création de données de test
    cat << EOF > "$metrics_file"
timestamp=1623456789
latency=45.2
packet_loss=0.1
mtu=1420
cpu_usage=2.5
mem_usage=35.8
EOF
    
    run analyze_performance_trends "$metrics_file"
    
    [ "$status" -eq 0 ]
    [ -f "${TEMP_DIR}/performance_trends" ]
}

@test "Génération des recommandations d'optimisation" {
    local temp_dir=$(mktemp -d)
    TEMP_DIR="$temp_dir"
    local trends_file="${TEMP_DIR}/performance_trends"
    
    # Création de données de tendances
    cat << EOF > "$trends_file"
metric,trend,variation
latency,15.5,55.2
packet_loss,6.2,1.2
EOF
    
    run generate_optimization_recommendations "$trends_file"
    
    [ "$status" -eq 0 ]
    [[ "$output" =~ "RECOMMENDATION" ]]
}

# Nettoyage après les tests
teardown() {
    if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
    fi
} 