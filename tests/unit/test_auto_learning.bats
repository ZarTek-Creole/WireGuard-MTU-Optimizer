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
    log_debug() { echo "DEBUG: $1" >&2; }
    
    export -f log_error
    export -f log_warning
    export -f log_info
    export -f log_debug
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
    
    # Initialisation du fichier des modèles
    cat << EOF > "$MODELS_FILE"
{
    "version": "1.0",
    "network_conditions": {}
}
EOF
    
    echo "Running analyze_performance_patterns with interface: $interface" >&2
    run analyze_performance_patterns "$interface"
    echo "Status: $status" >&2
    echo "Output: $output" >&2
    [ "$status" -eq 0 ]
    
    # Vérification des patterns
    local model=$(jq -r ".network_conditions.wg0" "$MODELS_FILE")
    echo "Model: $model" >&2
    
    # Vérification des tendances
    local latency_trend=$(echo "$model" | jq -r '.latency_trend.trend')
    echo "Latency trend: $latency_trend" >&2
    [[ "$latency_trend" != "null" ]]
    [[ "$latency_trend" =~ ^-?[0-9]+\.?[0-9]*$ ]]
    
    # Vérification des corrélations
    local correlation=$(echo "$model" | jq -r '.correlations.mtu_vs_performance')
    echo "Correlation: $correlation" >&2
    [[ "$correlation" != "null" ]]
    [[ "$correlation" =~ ^-?[0-9]+\.?[0-9]*$ ]]
    
    # Vérification des anomalies
    local anomalies=$(echo "$model" | jq -r '.anomalies.latency_spikes')
    echo "Anomalies: $anomalies" >&2
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
                "mtu_vs_performance": 0.85,
                "latency_vs_throughput": -0.75
            }
        }
    }
}
EOF
    
    # Initialisation du fichier des prédictions
    cat << EOF > "$PREDICTIONS_FILE"
{
    "version": "1.0",
    "predictions": {}
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
    # Setup test data
    local interface="wg0"
    local current_mtu=1350  # Set below optimal range
    
    # Setup model file with optimal conditions
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
                "mtu_vs_performance": 0.95,
                "latency_vs_throughput": -0.80
            }
        }
    }
}
EOF
    
    # Setup predictions file with optimal range that doesn't include current MTU
    cat << EOF > "$PREDICTIONS_FILE"
{
    "version": "1.0",
    "predictions": {
        "wg0": {
            "timestamp": "2025-01-16T14:10:17+01:00",
            "interface": "wg0",
            "current_mtu": 1350,
            "predictions": {
                "latency_trend": -0.5,
                "throughput_trend": 2,
                "packet_loss_trend": -0.01,
                "stability_prediction": 0.98,
                "optimal_mtu_range": {
                    "min": 1400,
                    "max": 1440
                },
                "confidence_score": 0.8770,
                "recommendations": {
                    "mtu_adjustment": "increase",
                    "expected_improvement": 0.8892,
                    "risk_level": "low"
                }
            }
        }
    }
}
EOF
    
    # Get new MTU recommendation
    run auto_adapt_mtu "$interface" "$current_mtu"
    
    # Extract the last line which contains only the MTU value
    new_mtu=$(echo "$output" | tail -n1)
    
    # Verify the command succeeded
    [ "$status" -eq 0 ]
    
    # Verify we got a valid MTU value
    [[ "$new_mtu" =~ ^[0-9]+$ ]]
    
    # Convert to integers and compare
    [ "$new_mtu" -ne "$current_mtu" ]
    
    # Verify the new MTU is within valid range
    [ "$new_mtu" -ge 1280 ]
    [ "$new_mtu" -le 1500 ]
}

# Test d'évaluation continue
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
    # Setup test data
    local model='{
        "stability_score": 0.95,
        "anomalies": {
            "latency_spikes": 1,
            "packet_loss_events": 0,
            "throughput_drops": 1
        },
        "correlations": {
            "mtu_vs_performance": 0.85,
            "latency_vs_throughput": -0.75
        },
        "optimal_conditions": {
            "time_ranges": [
                {"key": "12:00", "count": 5},
                {"key": "13:00", "count": 4}
            ]
        }
    }'
    
    # Calculate confidence score
    run calculate_confidence_score "$model"
    
    # Extract just the numeric score (last line)
    score=$(echo "$output" | tail -n1)
    
    # Verify the command succeeded
    [ "$status" -eq 0 ]
    
    # Verify the score is a valid floating point number between 0 and 1
    [[ "$score" =~ ^0\.[0-9]+$ ]]
    
    # Verify the score is within expected range
    result=$(echo "$score > 0.0 && $score <= 1.0" | bc -l)
    [ "$result" -eq 1 ]
}

# Test des cas limites pour l'initialisation
@test "Auto-Learning - Initialisation avec répertoire existant" {
    # Créer d'abord le répertoire et les fichiers
    mkdir -p "${LEARNING_DIR}/existing"
    export LEARNING_DIR="${LEARNING_DIR}/existing"
    
    # Tenter l'initialisation sur un répertoire existant
    run init_learning_system
    [ "$status" -eq 0 ]
    
    # Vérifier que les fichiers sont toujours valides
    [ -f "$HISTORY_FILE" ]
    [ -f "$MODELS_FILE" ]
    [ -f "$PREDICTIONS_FILE" ]
    
    # Vérifier la structure JSON
    run jq '.' "$HISTORY_FILE"
    [ "$status" -eq 0 ]
    run jq '.' "$MODELS_FILE"
    [ "$status" -eq 0 ]
    run jq '.' "$PREDICTIONS_FILE"
    [ "$status" -eq 0 ]
}

# Test des cas limites pour l'enregistrement des données
@test "Auto-Learning - Enregistrement avec données invalides" {
    local interface="wg0"
    local metrics_file="${TEMP_DIR}/invalid_metrics.json"
    
    # Créer des données de test invalides
    echo "invalid json" > "$metrics_file"
    
    # Tenter l'enregistrement avec des données invalides
    run record_performance_data "$interface" "$metrics_file"
    [ "$status" -eq 1 ]
    
    # Vérifier que le fichier d'historique n'a pas été corrompu
    run jq '.' "$HISTORY_FILE"
    [ "$status" -eq 0 ]
}

# Test des cas limites pour l'analyse des patterns
@test "Auto-Learning - Analyse avec données insuffisantes" {
    local interface="wg0"
    
    # Créer un historique vide
    cat << EOF > "$HISTORY_FILE"
{
    "version": "1.0",
    "last_update": "$(date -Iseconds)",
    "performance_records": []
}
EOF
    
    # Tenter l'analyse avec des données insuffisantes
    run analyze_performance_patterns "$interface"
    [ "$status" -eq 1 ]
    
    # Vérifier le message d'erreur
    [[ "$output" =~ "Aucune donnée trouvée" ]]
}

# Test des cas limites pour la prédiction
@test "Auto-Learning - Prédiction avec MTU hors limites" {
    local interface="wg0"
    local invalid_mtu=2000
    
    # Tenter la prédiction avec un MTU invalide
    run predict_performance "$interface" "$invalid_mtu"
    [ "$status" -eq 1 ]
    
    # Vérifier que le fichier de prédictions n'a pas été modifié
    local original_content=$(cat "$PREDICTIONS_FILE")
    run predict_performance "$interface" "$invalid_mtu"
    [ "$(cat "$PREDICTIONS_FILE")" = "$original_content" ]
}

# Test des cas limites pour l'adaptation MTU
@test "Auto-Learning - Adaptation avec valeurs limites" {
    local interface="wg0"
    
    # Setup model file with optimal conditions
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
                "mtu_vs_performance": 0.95,
                "latency_vs_throughput": -0.80
            }
        }
    }
}
EOF
    
    echo "Testing minimum MTU (1280)..." >&2
    # Test avec MTU minimum
    run auto_adapt_mtu "$interface" "1280"
    echo "Status: $status" >&2
    echo "Output: $output" >&2
    [ "$status" -eq 0 ]
    local new_mtu=$(echo "$output" | tail -n1)
    [ "$new_mtu" -ge 1280 ]
    
    echo "Testing maximum MTU (1500)..." >&2
    # Test avec MTU maximum
    run auto_adapt_mtu "$interface" "1500"
    echo "Status: $status" >&2
    echo "Output: $output" >&2
    [ "$status" -eq 0 ]
    new_mtu=$(echo "$output" | tail -n1)
    [ "$new_mtu" -le 1500 ]
    
    echo "Testing invalid MTU (1000)..." >&2
    # Test avec MTU invalide
    run auto_adapt_mtu "$interface" "1000"
    echo "Status: $status" >&2
    echo "Output: $output" >&2
    [ "$status" -eq 1 ]
}

# Test des cas limites pour le score de confiance
@test "Auto-Learning - Score de confiance avec données extrêmes" {
    # Test avec stabilité maximale
    local model_max='{
        "stability_score": 1.0,
        "anomalies": {
            "latency_spikes": 0,
            "packet_loss_events": 0,
            "throughput_drops": 0
        },
        "correlations": {
            "mtu_vs_performance": 1.0,
            "latency_vs_throughput": -1.0
        },
        "optimal_conditions": {
            "time_ranges": [
                {"key": "12:00", "count": 100}
            ]
        }
    }'
    
    echo "Testing maximum stability model..." >&2
    run calculate_confidence_score "$model_max"
    score=$(echo "$output" | tail -n1)
    echo "Max stability score: $score" >&2
    [ "$status" -eq 0 ]
    [[ "$score" =~ ^[0-1]\.[0-9]+$|^1\.0+$ ]]
    result=$(echo "$score >= 0.9" | bc -l)
    echo "Max stability result: $result" >&2
    [ "$result" -eq 1 ]
    
    # Test avec stabilité minimale
    local model_min='{
        "stability_score": 0.0,
        "anomalies": {
            "latency_spikes": 10,
            "packet_loss_events": 10,
            "throughput_drops": 10
        },
        "correlations": {
            "mtu_vs_performance": 0.0,
            "latency_vs_throughput": 0.0
        },
        "optimal_conditions": {
            "time_ranges": []
        }
    }'
    
    echo "Testing minimum stability model..." >&2
    run calculate_confidence_score "$model_min"
    score=$(echo "$output" | tail -n1)
    echo "Min stability score: $score" >&2
    [ "$status" -eq 0 ]
    [[ "$score" =~ ^[0-1]\.[0-9]+$|^1\.0+$ ]]
    result=$(echo "$score < 0.3" | bc -l)
    echo "Min stability result: $result" >&2
    [ "$result" -eq 1 ]
}

# Nettoyage
teardown() {
    if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
    fi
} 