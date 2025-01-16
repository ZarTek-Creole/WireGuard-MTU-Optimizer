#!/usr/bin/env bats

load '../test_helper'
load '../../lib/auto_learning.sh'

# Configuration pour les tests
setup() {
    export TEMP_DIR=$(mktemp -d)
    export LEARNING_DIR="${TEMP_DIR}/learning"
    export HISTORY_FILE="${LEARNING_DIR}/performance_history.json"
    export MODELS_FILE="${LEARNING_DIR}/optimization_models.json"
    export PREDICTIONS_FILE="${LEARNING_DIR}/performance_predictions.json"
    
    mkdir -p "$LEARNING_DIR"
    init_learning_system
    
    # Fonctions de logging simulées
    log_error() { echo "ERROR: $1" >&2; }
    log_warning() { echo "WARNING: $1" >&2; }
    log_info() { echo "INFO: $1" >&2; }
    
    export -f log_error
    export -f log_warning
    export -f log_info
}

# Test d'initialisation
@test "Auto-Learning - Initialisation du système" {
    [ -f "$HISTORY_FILE" ]
    [ -f "$MODELS_FILE" ]
    
    # Vérification de la structure JSON
    run jq '.' "$HISTORY_FILE"
    [ "$status" -eq 0 ]
    
    run jq '.' "$MODELS_FILE"
    [ "$status" -eq 0 ]
}

# Test d'enregistrement des données
@test "Auto-Learning - Enregistrement des données de performance" {
    local interface="wg0"
    local metrics_file="${TEMP_DIR}/metrics.json"
    
    # Création de données de test
    cat << EOF > "$metrics_file"
{
    "latency": 45.2,
    "throughput": 120.5,
    "packet_loss": 0.1,
    "jitter": 2.3,
    "mtu": 1420,
    "performance_score": 0.95
}
EOF
    
    run record_performance_data "$interface" "$metrics_file"
    [ "$status" -eq 0 ]
    
    # Vérification de l'enregistrement
    local count=$(jq '.performance_records | length' "$HISTORY_FILE")
    [ "$count" -eq 1 ]
}

# Test d'analyse des patterns
@test "Auto-Learning - Analyse des patterns de performance" {
    local interface="wg0"
    
    # Création de données historiques avec tendances
    cat << EOF > "$HISTORY_FILE"
{
    "version": "1.0",
    "last_update": "$(date -Iseconds)",
    "performance_records": [
        {
            "timestamp": "$(date -d '1 hour ago' -Iseconds)",
            "interface": "wg0",
            "metrics": {
                "latency": 40.0,
                "throughput": 100.0,
                "packet_loss": 0.1,
                "jitter": 2.0,
                "mtu": 1400,
                "performance_score": 0.95
            }
        },
        {
            "timestamp": "$(date -Iseconds)",
            "interface": "wg0",
            "metrics": {
                "latency": 45.0,
                "throughput": 110.0,
                "packet_loss": 0.2,
                "jitter": 2.5,
                "mtu": 1420,
                "performance_score": 0.92
            }
        }
    ]
}
EOF
    
    run analyze_performance_patterns "$interface"
    [ "$status" -eq 0 ]
    
    # Vérification des patterns
    local model=$(jq -r ".network_conditions.wg0" "$MODELS_FILE")
    
    # Vérification des tendances
    local latency_trend=$(echo "$model" | jq -r '.latency_trend.trend')
    [[ "$latency_trend" != "null" ]]
    [[ "$latency_trend" =~ ^-?[0-9]+\.[0-9]+$ ]]
    
    # Vérification des corrélations
    local correlation=$(echo "$model" | jq -r '.correlations.mtu_vs_performance')
    [[ "$correlation" != "null" ]]
    [[ "$correlation" =~ ^-?[0-9]+\.[0-9]+$ ]]
    
    # Vérification des anomalies
    local anomalies=$(echo "$model" | jq -r '.anomalies.latency_spikes')
    [[ "$anomalies" =~ ^[0-9]+$ ]]
}

# Test de prédiction des performances
@test "Auto-Learning - Prédiction des performances" {
    local interface="wg0"
    local current_mtu=1400
    
    # Configuration du modèle avec données détaillées
    cat << EOF > "$MODELS_FILE"
{
    "version": "1.0",
    "network_conditions": {
        "wg0": {
            "latency_trend": {
                "avg": 42.5,
                "trend": 0.5
            },
            "throughput_trend": {
                "avg": 105.0,
                "trend": 1.0
            },
            "packet_loss_trend": {
                "avg": 0.15,
                "trend": 0.01
            },
            "stability_score": 0.98,
            "optimal_conditions": {
                "mtu": 1420,
                "time_ranges": [
                    {"key": "12:00", "count": 10}
                ]
            },
            "anomalies": {
                "latency_spikes": 1,
                "packet_loss_events": 0,
                "throughput_drops": 1
            },
            "correlations": {
                "mtu_vs_performance": 0.85
            }
        }
    }
}
EOF
    
    run predict_performance "$interface" "$current_mtu"
    [ "$status" -eq 0 ]
    
    # Vérification des prédictions
    [ -f "$PREDICTIONS_FILE" ]
    
    local predictions=$(cat "$PREDICTIONS_FILE")
    
    # Vérification des champs requis
    local confidence_score=$(echo "$predictions" | jq -r '.predictions.confidence_score')
    [[ "$confidence_score" =~ ^0\.[0-9]+$ ]]
    
    local risk_level=$(echo "$predictions" | jq -r '.predictions.recommendations.risk_level')
    [[ "$risk_level" == "low" || "$risk_level" == "medium" ]]
    
    local expected_improvement=$(echo "$predictions" | jq -r '.predictions.recommendations.expected_improvement')
    [[ "$expected_improvement" =~ ^0\.[0-9]+$ ]]
}

# Test d'adaptation MTU
@test "Auto-Learning - Adaptation MTU avec analyse de risque" {
    local interface="wg0"
    local current_mtu=1400
    
    # Configuration du modèle avec données optimales
    cat << EOF > "$MODELS_FILE"
{
    "version": "1.0",
    "network_conditions": {
        "wg0": {
            "latency_trend": {
                "avg": 42.5,
                "trend": -0.5
            },
            "throughput_trend": {
                "avg": 105.0,
                "trend": 2.0
            },
            "packet_loss_trend": {
                "avg": 0.15,
                "trend": -0.01
            },
            "stability_score": 0.98,
            "optimal_conditions": {
                "mtu": 1420,
                "time_ranges": [
                    {"key": "12:00", "count": 10}
                ]
            },
            "anomalies": {
                "latency_spikes": 0,
                "packet_loss_events": 0,
                "throughput_drops": 0
            },
            "correlations": {
                "mtu_vs_performance": 0.95
            }
        }
    }
}
EOF
    
    run auto_adapt_mtu "$interface" "$current_mtu"
    [ "$status" -eq 0 ]
    
    # Vérification de l'adaptation
    local new_mtu=$output
    [ "$new_mtu" -ne "$current_mtu" ]
    
    # Vérification des limites
    [ "$new_mtu" -ge 1280 ]
    [ "$new_mtu" -le 1500 ]
}

# Test d'évaluation continue avec seuil d'adaptation
@test "Auto-Learning - Évaluation continue avec seuil d'adaptation" {
    skip "Test d'évaluation continue désactivé temporairement"
    local interface="wg0"
    
    # Simulation des fonctions requises
    collect_current_metrics() {
        echo '{"metrics": "test"}'
    }
    
    record_performance_data() {
        return 0
    }
    
    update_wireguard_mtu() {
        return 0
    }
    
    export -f collect_current_metrics
    export -f record_performance_data
    export -f update_wireguard_mtu
    
    # Démarrage de l'évaluation en arrière-plan avec un intervalle court pour le test
    evaluation_interval=1
    run continuous_evaluation "$interface" &
    local eval_pid=$!
    
    # Attente pour quelques cycles d'évaluation
    sleep 5
    
    # Arrêt du processus
    kill "$eval_pid"
    
    # Vérification des fichiers de données
    [ -f "$HISTORY_FILE" ]
    [ -f "$MODELS_FILE" ]
    [ -f "$PREDICTIONS_FILE" ]
}

# Test de calcul du score de confiance
@test "Auto-Learning - Calcul du score de confiance" {
    local model='{
        "stability_score": 0.95,
        "anomalies": {
            "latency_spikes": 1,
            "packet_loss_events": 0,
            "throughput_drops": 1
        },
        "correlations": {
            "mtu_vs_performance": 0.85
        },
        "optimal_conditions": {
            "time_ranges": [
                {"key": "12:00", "count": 5},
                {"key": "13:00", "count": 4}
            ]
        }
    }'
    
    run calculate_confidence_score "$model"
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^0\.[0-9]+$ ]]
    
    # Le score doit être entre 0 et 1
    local score=$output
    [ $(echo "$score <= 1.0" | bc -l) -eq 1 ]
    [ $(echo "$score >= 0.0" | bc -l) -eq 1 ]
}

# Nettoyage
teardown() {
    if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
    fi
} 