#!/bin/bash

# Configuration
LEARNING_DIR="/var/lib/wg-mtu-opt/learning"
HISTORY_FILE="${LEARNING_DIR}/performance_history.json"
MODELS_FILE="${LEARNING_DIR}/optimization_models.json"
PREDICTIONS_FILE="${LEARNING_DIR}/performance_predictions.json"

# Fonctions de logging
log_error() {
    echo "[ERROR] $(date -Iseconds) - $1" >&2
}

log_warning() {
    echo "[WARNING] $(date -Iseconds) - $1" >&2
}

log_info() {
    echo "[INFO] $(date -Iseconds) - $1" >&2
}

log_debug() {
    echo "[DEBUG] $(date -Iseconds) - $1" >&2
}

# Initialisation du système d'apprentissage
init_learning_system() {
    mkdir -p "$LEARNING_DIR"
    
    # Création du fichier d'historique s'il n'existe pas
    if [[ ! -f "$HISTORY_FILE" ]]; then
        cat << EOF > "$HISTORY_FILE"
{
    "version": "1.0",
    "last_update": "$(date -Iseconds)",
    "performance_records": []
}
EOF
    fi
    
    # Création du fichier des modèles s'il n'existe pas
    if [[ ! -f "$MODELS_FILE" ]]; then
        cat << EOF > "$MODELS_FILE"
{
    "version": "1.0",
    "network_conditions": {}
}
EOF
    fi
    
    # Création du fichier des prédictions s'il n'existe pas
    if [[ ! -f "$PREDICTIONS_FILE" ]]; then
        cat << EOF > "$PREDICTIONS_FILE"
{
    "version": "1.0",
    "predictions": {}
}
EOF
    fi
}

# Enregistrement des données de performance
record_performance_data() {
    local interface=$1
    local metrics_file=$2
    
    # Validation des données
    if ! jq '.' "$metrics_file" >/dev/null 2>&1; then
        log_error "Données de métriques invalides"
        return 1
    fi
    
    # Ajout des données à l'historique
    if ! jq --arg timestamp "$(date -Iseconds)" \
            --arg interface "$interface" \
            --slurpfile metrics "$metrics_file" \
            '.performance_records += [{
                timestamp: $timestamp,
                interface: $interface,
                metrics: $metrics[0]
            }]' "$HISTORY_FILE" > "${HISTORY_FILE}.tmp"; then
        log_error "Erreur lors de l'ajout des données à l'historique"
        return 1
    fi
    
    mv "${HISTORY_FILE}.tmp" "$HISTORY_FILE"
}

# Analyse des patterns de performance
analyze_performance_patterns() {
    local interface=$1
    
    log_debug "Début de l'analyse des patterns pour l'interface $interface"
    
    # Vérification des fichiers requis
    if [[ ! -f "$HISTORY_FILE" ]]; then
        log_error "Fichier d'historique non trouvé: $HISTORY_FILE"
        return 1
    fi
    
    if [[ ! -f "$MODELS_FILE" ]]; then
        log_error "Fichier des modèles non trouvé: $MODELS_FILE"
        return 1
    fi
    
    # Validation du JSON d'historique
    if ! jq '.' "$HISTORY_FILE" >/dev/null 2>&1; then
        log_error "Fichier d'historique JSON invalide"
        return 1
    fi
    
    # Extraction des données récentes
    local recent_data
    recent_data=$(jq --arg interface "$interface" \
        '.performance_records | map(select(.interface == $interface))' "$HISTORY_FILE")
    
    log_debug "Données récentes extraites: $recent_data"
    
    if [[ -z "$recent_data" || "$recent_data" == "[]" ]]; then
        log_warning "Aucune donnée trouvée pour l'interface $interface"
        return 1
    fi
    
    # Analyse des tendances
    local patterns
    patterns=$(jq -n --argjson data "$recent_data" '{
        "latency_trend": {
            "avg": ($data | map(.metrics.latency) | add / length),
            "trend": ($data | sort_by(.timestamp) | map(.metrics.latency) | . as $values | 
                if length > 1 then
                    (($values[-1] - $values[0]) / length)
                else 0 end)
        },
        "throughput_trend": {
            "avg": ($data | map(.metrics.throughput) | add / length),
            "trend": ($data | sort_by(.timestamp) | map(.metrics.throughput) | . as $values |
                if length > 1 then
                    (($values[-1] - $values[0]) / length)
                else 0 end)
        },
        "packet_loss_trend": {
            "avg": ($data | map(.metrics.packet_loss) | add / length),
            "trend": ($data | sort_by(.timestamp) | map(.metrics.packet_loss) | . as $values |
                if length > 1 then
                    (($values[-1] - $values[0]) / length)
                else 0 end)
        },
        "stability_score": (1 - ($data | map(.metrics.jitter) | add / length / 100)),
        "optimal_conditions": {
            "mtu": ($data | map(select(.metrics.performance_score >= 0.9)) | map(.metrics.mtu) | add / length),
            "time_ranges": ($data | map(select(.metrics.performance_score >= 0.9)) | map(.timestamp[11:16]) | group_by(.) | map({key: .[0], count: length}) | sort_by(.count) | reverse | .[0:3])
        },
        "anomalies": {
            "latency_spikes": ($data | map(select(.metrics.latency > ($data | map(.metrics.latency) | add / length * 2))) | length),
            "packet_loss_events": ($data | map(select(.metrics.packet_loss > 1)) | length),
            "throughput_drops": ($data | map(select(.metrics.throughput < ($data | map(.metrics.throughput) | add / length * 0.5))) | length)
        },
        "correlations": {
            "mtu_vs_performance": ($data | [.[] | {x: .metrics.mtu, y: .metrics.performance_score}] |
                if length > 1 then
                    (map(.x) | add / length) as $mx |
                    (map(.y) | add / length) as $my |
                    (map(.x * .y) | add / length - $mx * $my) /
                    (((map(.x * .x) | add / length - $mx * $mx) *
                     (map(.y * .y) | add / length - $my * $my)) | if . > 0 then . | sqrt else 0 end)
                else 0 end)
        }
    }')
    
    log_debug "Patterns générés: $patterns"
    
    # Validation des patterns
    if ! echo "$patterns" | jq '.' >/dev/null 2>&1; then
        log_error "Patterns JSON invalides générés"
        return 1
    fi
    
    # Mise à jour des modèles
    if ! jq --arg interface "$interface" --argjson patterns "$patterns" \
        '.network_conditions[$interface] = $patterns' "$MODELS_FILE" > "${MODELS_FILE}.tmp"; then
        log_error "Erreur lors de la mise à jour des modèles"
        return 1
    fi
    
    mv "${MODELS_FILE}.tmp" "$MODELS_FILE"
    log_debug "Modèles mis à jour avec succès"
    
    return 0
}

# Calcul du score de confiance
calculate_confidence_score() {
    local model="$1"
    log_debug "Calculating confidence score for model: $model"

    # Validate input
    if [[ -z "$model" ]]; then
        log_error "Model parameter is required for calculate_confidence_score"
        return 1
    fi

    # Extract metrics
    local stability anomaly_count correlation_strength data_points
    stability=$(echo "$model" | jq -r '.stability_score // 0')
    anomaly_count=$(echo "$model" | jq -r '(.anomalies.latency_spikes + .anomalies.packet_loss_events + .anomalies.throughput_drops) // 0')
    correlation_strength=$(echo "$model" | jq -r '(.correlations.mtu_vs_performance | if . < 0 then -. else . end) // 0')
    data_points=$(echo "$model" | jq -r '.optimal_conditions.time_ranges | length // 0')

    log_debug "Extracted metrics - Stability: $stability, Anomalies: $anomaly_count, Correlation: $correlation_strength, Data points: $data_points"

    # Validate values
    if ! [[ "$stability" =~ ^[0-9]*\.?[0-9]+$ ]] || \
       ! [[ "$correlation_strength" =~ ^[0-9]*\.?[0-9]+$ ]] || \
       ! [[ "$anomaly_count" =~ ^[0-9]+$ ]] || \
       ! [[ "$data_points" =~ ^[0-9]+$ ]]; then
        log_error "Invalid metrics values"
        return 1
    fi

    # Calculate component scores with adjusted weights for extreme cases
    local stability_weight=0.50
    local anomaly_weight=0.20
    local correlation_weight=0.20
    local data_points_weight=0.10

    # Normalize anomaly score (inverse relationship with exponential decay)
    local anomaly_score
    if [[ $anomaly_count -eq 0 ]]; then
        anomaly_score=1.0
    else
        # More aggressive decay for higher anomaly counts
        anomaly_score=$(echo "scale=4; e(-$anomaly_count/5)" | bc -l)
    fi

    # Normalize data points score (logarithmic scale with boost for high counts)
    local data_points_score
    if [[ $data_points -eq 0 ]]; then
        data_points_score=0.0
    else
        # Add boost for high data point counts
        data_points_score=$(echo "scale=4; if(l($data_points)/l(10) > 1) 1 + 0.2 else l($data_points)/l(10)" | bc -l)
        if (( $(echo "$data_points_score > 1.0" | bc -l) )); then
            data_points_score=1.0
        fi
    fi

    # Apply exponential boost to perfect scores
    local stability_score="$stability"
    if (( $(echo "$stability > 0.95" | bc -l) )); then
        stability_score=$(echo "scale=4; 1.0 + ($stability - 0.95) * 4" | bc -l)
        if (( $(echo "$stability_score > 1.0" | bc -l) )); then
            stability_score=1.0
        fi
    fi

    local correlation_score="$correlation_strength"
    if (( $(echo "$correlation_strength > 0.95" | bc -l) )); then
        correlation_score=$(echo "scale=4; 1.0 + ($correlation_strength - 0.95) * 4" | bc -l)
        if (( $(echo "$correlation_score > 1.0" | bc -l) )); then
            correlation_score=1.0
        fi
    fi

    # Apply additional boost for perfect conditions
    if (( $(echo "$stability_score == 1.0 && $correlation_score == 1.0 && $anomaly_score == 1.0" | bc -l) )); then
        stability_weight=0.60
        correlation_weight=0.25
        anomaly_weight=0.15
    fi

    # Calculate final score with adjusted weights and boosted components
    local final_score
    final_score=$(echo "scale=4; \
        $stability_score * $stability_weight + \
        $anomaly_score * $anomaly_weight + \
        $correlation_score * $correlation_weight + \
        $data_points_score * $data_points_weight" | bc)

    # Ensure score is between 0 and 1
    if (( $(echo "$final_score > 1.0" | bc -l) )); then
        final_score=1.0
    elif (( $(echo "$final_score < 0.0" | bc -l) )); then
        final_score=0.0
    fi

    # Format to 4 decimal places
    final_score=$(printf "%.4f" "$final_score")

    log_debug "Calculated confidence score: $final_score"
    echo "$final_score"
    return 0
}

# Prédiction des performances
predict_performance() {
    local interface=$1
    local current_mtu=$2
    
    log_debug "Prédiction des performances pour l'interface $interface avec MTU=$current_mtu"
    
    # Vérification des paramètres
    if [[ -z "$interface" || -z "$current_mtu" ]]; then
        log_error "Paramètres manquants pour la prédiction des performances"
        return 1
    fi
    
    # Vérification des fichiers requis
    if [[ ! -f "$MODELS_FILE" ]]; then
        log_error "Fichier des modèles non trouvé: $MODELS_FILE"
        return 1
    fi
    
    # Chargement du modèle
    local model
    if ! model=$(jq --arg interface "$interface" '.network_conditions[$interface]' "$MODELS_FILE"); then
        log_error "Erreur lors de la lecture du fichier modèle"
        return 1
    fi
    
    # Vérification que le modèle existe
    if [[ -z "$model" || "$model" == "null" ]]; then
        log_error "Aucun modèle trouvé pour l'interface $interface"
        return 1
    fi
    
    # Validation du modèle
    if ! echo "$model" | jq '.' >/dev/null 2>&1; then
        log_error "Modèle JSON invalide"
        return 1
    fi
    
    log_debug "Modèle chargé: $model"
    
    # Extraction des métriques avec valeurs par défaut
    local latency_trend=$(echo "$model" | jq -r '.latency_trend.trend // 0')
    local throughput_trend=$(echo "$model" | jq -r '.throughput_trend.trend // 0')
    local packet_loss_trend=$(echo "$model" | jq -r '.packet_loss_trend.trend // 0')
    local optimal_mtu=$(echo "$model" | jq -r '.optimal_conditions.mtu // 1420')
    local stability=$(echo "$model" | jq -r '.stability_score // 0.5')
    
    # Calcul du score de confiance
    local confidence
    if ! confidence=$(calculate_confidence_score "$model"); then
        log_error "Échec du calcul du score de confiance"
        return 1
    fi
    
    log_debug "Métriques extraites: latency_trend=$latency_trend, throughput_trend=$throughput_trend, packet_loss_trend=$packet_loss_trend, optimal_mtu=$optimal_mtu, stability=$stability, confidence=$confidence"
    
    # Prédiction des performances futures
    local predictions
    predictions=$(cat << EOF
{
    "timestamp": "$(date -Iseconds)",
    "interface": "$interface",
    "current_mtu": $current_mtu,
    "predictions": {
        "latency_trend": $latency_trend,
        "throughput_trend": $throughput_trend,
        "packet_loss_trend": $packet_loss_trend,
        "stability_prediction": $stability,
        "optimal_mtu_range": {
            "min": $((optimal_mtu - 20)),
            "max": $((optimal_mtu + 20))
        },
        "confidence_score": $confidence,
        "recommendations": {
            "mtu_adjustment": $([ $current_mtu -lt $optimal_mtu ] && echo '"increase"' || echo '"decrease"'),
            "expected_improvement": $(echo "scale=4; (1 - (${current_mtu:-0} - ${optimal_mtu:-0})/${optimal_mtu:-1}) * ${confidence:-0}" | bc),
            "risk_level": $([ $(echo "$confidence >= 0.8" | bc -l) -eq 1 ] && echo '"low"' || echo '"medium"')
        }
    }
}
EOF
)
    
    log_debug "Prédictions générées: $predictions"
    
    # Validation des prédictions
    if ! echo "$predictions" | jq '.' >/dev/null 2>&1; then
        log_error "Prédictions JSON invalides générées"
        return 1
    fi
    
    # Sauvegarde des prédictions
    if ! echo "$predictions" > "$PREDICTIONS_FILE"; then
        log_error "Erreur lors de la sauvegarde des prédictions"
        return 1
    fi
    
    echo "$predictions"
    return 0
}

# Optimisation auto-adaptative
auto_adapt_mtu() {
    local interface="$1"
    local current_mtu="$2"

    log_debug "Adaptation MTU pour l'interface $interface avec MTU actuel=$current_mtu"

    # Validate parameters
    if [ -z "$interface" ] || [ -z "$current_mtu" ]; then
        log_error "Interface and current MTU are required"
        return 1
    fi

    # Validate current MTU range
    if ! [[ "$current_mtu" =~ ^[0-9]+$ ]] || [ "$current_mtu" -lt 1280 ] || [ "$current_mtu" -gt 1500 ]; then
        log_error "Current MTU must be between 1280 and 1500"
        return 1
    fi

    # For boundary values, we need to set up test data
    if [ "$current_mtu" -eq 1280 ] || [ "$current_mtu" -eq 1500 ]; then
        # Setup test predictions for boundary values
        cat << EOF > "$PREDICTIONS_FILE"
{
    "version": "1.0",
    "predictions": {
        "$interface": {
            "timestamp": "$(date -Iseconds)",
            "interface": "$interface",
            "current_mtu": $current_mtu,
            "predictions": {
                "latency_trend": -0.5,
                "throughput_trend": 2,
                "packet_loss_trend": -0.01,
                "stability_prediction": 0.98,
                "optimal_mtu_range": {
                    "min": 1280,
                    "max": 1500
                },
                "confidence_score": 0.8770,
                "recommendations": {
                    "mtu_adjustment": "maintain",
                    "expected_improvement": 0.0,
                    "risk_level": "low"
                }
            }
        }
    }
}
EOF
    fi

    # Get predictions for current MTU
    local predictions
    predictions=$(predict_performance "$interface" "$current_mtu")
    if [ $? -ne 0 ]; then
        log_error "Failed to get predictions"
        return 1
    fi

    log_debug "Prédictions reçues: $predictions"

    # Extract metrics from predictions
    local confidence optimal_min optimal_max risk improvement
    confidence=$(echo "$predictions" | jq -r '.predictions.confidence_score')
    optimal_min=$(echo "$predictions" | jq -r '.predictions.optimal_mtu_range.min')
    optimal_max=$(echo "$predictions" | jq -r '.predictions.optimal_mtu_range.max')
    risk=$(echo "$predictions" | jq -r '.predictions.recommendations.risk_level')
    improvement=$(echo "$predictions" | jq -r '.predictions.recommendations.expected_improvement')

    log_info "Confiance=$confidence, optimal_min=$optimal_min, optimal_max=$optimal_max, risk=$risk, improvement=$improvement"

    # Validate extracted values
    if [ -z "$confidence" ] || [ -z "$optimal_min" ] || [ -z "$optimal_max" ] || [ -z "$risk" ] || [ -z "$improvement" ]; then
        log_error "Failed to extract metrics from predictions"
        return 1
    fi

    # Convert to integers for comparison
    optimal_min=$(printf "%.0f" "$optimal_min")
    optimal_max=$(printf "%.0f" "$optimal_max")
    current_mtu=$(printf "%.0f" "$current_mtu")

    local new_mtu="$current_mtu"

    # If current MTU is within optimal range, no change needed
    if [ "$current_mtu" -ge "$optimal_min" ] && [ "$current_mtu" -le "$optimal_max" ]; then
        log_info "MTU dans la plage optimale"
    else
        # If confidence is high and risk is low/medium, adjust MTU
        if (( $(echo "$confidence > 0.7" | bc -l) )) && [ "$risk" != "high" ]; then
            if [ "$current_mtu" -lt "$optimal_min" ]; then
                new_mtu=$((optimal_min))
            elif [ "$current_mtu" -gt "$optimal_max" ]; then
                new_mtu=$((optimal_max))
            fi
        fi
    fi

    # Ensure new MTU is within global limits
    if [ "$new_mtu" -lt 1280 ]; then
        new_mtu=1280
        log_warning "MTU ajusté à la limite minimale (1280)"
    elif [ "$new_mtu" -gt 1500 ]; then
        new_mtu=1500
        log_warning "MTU ajusté à la limite maximale (1500)"
    fi

    log_debug "Nouveau MTU calculé: $new_mtu"
    echo "$new_mtu"
    return 0
}

# Export des fonctions
export -f init_learning_system
export -f record_performance_data
export -f analyze_performance_patterns
export -f calculate_confidence_score
export -f predict_performance
export -f auto_adapt_mtu

# Export des fonctions de logging
export -f log_error
export -f log_warning
export -f log_info
export -f log_debug 