#!/bin/bash

# Système d'auto-apprentissage pour WireGuard MTU Optimizer

# Structure des données d'apprentissage
LEARNING_DIR="/var/lib/wg-mtu-opt/learning"
HISTORY_FILE="${LEARNING_DIR}/performance_history.json"
MODELS_FILE="${LEARNING_DIR}/optimization_models.json"
PREDICTIONS_FILE="${LEARNING_DIR}/performance_predictions.json"

# Initialisation du système d'apprentissage
init_learning_system() {
    mkdir -p "$LEARNING_DIR"
    
    # Création du fichier d'historique s'il n'existe pas
    if [[ ! -f "$HISTORY_FILE" ]]; then
        cat << EOF > "$HISTORY_FILE"
{
    "version": "1.0",
    "last_update": "$(date -Iseconds)",
    "performance_records": [],
    "optimization_history": []
}
EOF
    fi
    
    # Création du fichier des modèles
    if [[ ! -f "$MODELS_FILE" ]]; then
        cat << EOF > "$MODELS_FILE"
{
    "version": "1.0",
    "last_update": "$(date -Iseconds)",
    "network_conditions": {},
    "mtu_models": {},
    "performance_patterns": {}
}
EOF
    fi
}

# Enregistrement des données de performance
record_performance_data() {
    local interface=$1
    local metrics_file=$2
    
    # Lecture des métriques actuelles
    local timestamp=$(date -Iseconds)
    local metrics=$(cat "$metrics_file")
    
    # Création de l'enregistrement JSON
    local record=$(cat << EOF
{
    "timestamp": "$timestamp",
    "interface": "$interface",
    "metrics": $metrics,
    "system_state": {
        "cpu_usage": "$(top -bn1 | grep "Cpu(s)" | awk '{print $2}')",
        "memory_usage": "$(free | awk '/Mem/{printf("%.2f"), $3/$2*100}')",
        "network_load": "$(netstat -i | awk -v interface="$interface" '$1==interface {print $3 + $7}')"
    }
}
EOF
)
    
    # Ajout à l'historique
    jq --arg record "$record" '.performance_records += [$record]' "$HISTORY_FILE" > "${HISTORY_FILE}.tmp"
    mv "${HISTORY_FILE}.tmp" "$HISTORY_FILE"
}

# Analyse des patterns de performance
analyze_performance_patterns() {
    local interface=$1
    
    # Extraction des données récentes
    local recent_data=$(jq --arg interface "$interface" \
        '.performance_records | map(select(.interface == $interface))' "$HISTORY_FILE")
    
    # Analyse des tendances
    local patterns=$(jq -n --argjson data "$recent_data" '{
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
            "time_ranges": ($data | map(select(.metrics.performance_score >= 0.9)) | map(.timestamp[11:16]) | group_by(.) | map({key: .[0], count: length}) | sort_by(.count) | reverse | .[0:3]),
            "network_conditions": ($data | map(select(.metrics.performance_score >= 0.9)) | reduce .[] as $item ({};
                .[$item.timestamp[11:13]] += 1))
        },
        "anomalies": {
            "latency_spikes": ($data | map(select(.metrics.latency > ($data | map(.metrics.latency) | add / length * 2))) | length),
            "packet_loss_events": ($data | map(select(.metrics.packet_loss > 1)) | length),
            "throughput_drops": ($data | map(select(.metrics.throughput < ($data | map(.metrics.throughput) | add / length * 0.5))) | length)
        },
        "correlations": {
            "latency_vs_throughput": ($data | [.[] | {x: .metrics.latency, y: .metrics.throughput}] | 
                if length > 1 then
                    (map(.x) | add / length) as $mx |
                    (map(.y) | add / length) as $my |
                    (map(.x * .y) | add / length - $mx * $my) /
                    (sqrt((map(.x * .x) | add / length - $mx * $mx) *
                         (map(.y * .y) | add / length - $my * $my)))
                else 0 end),
            "mtu_vs_performance": ($data | [.[] | {x: .metrics.mtu, y: .metrics.performance_score}] |
                if length > 1 then
                    (map(.x) | add / length) as $mx |
                    (map(.y) | add / length) as $my |
                    (map(.x * .y) | add / length - $mx * $my) /
                    (sqrt((map(.x * .x) | add / length - $mx * $mx) *
                         (map(.y * .y) | add / length - $my * $my)))
                else 0 end)
        }
    }')
    
    # Mise à jour des modèles
    jq --arg interface "$interface" --argjson patterns "$patterns" \
        '.network_conditions[$interface] = $patterns' "$MODELS_FILE" > "${MODELS_FILE}.tmp"
    mv "${MODELS_FILE}.tmp" "$MODELS_FILE"
}

# Gestion des erreurs
log_error() {
    local message="$1"
    echo "[ERROR] $(date -Iseconds) - $message" >&2
}

log_warning() {
    local message="$1"
    echo "[WARNING] $(date -Iseconds) - $message" >&2
}

log_info() {
    local message="$1"
    echo "[INFO] $(date -Iseconds) - $message" >&2
}

handle_error() {
    local error_code=$1
    local message="$2"
    local fallback_action="$3"
    
    log_error "$message"
    
    case "$error_code" in
        1) # Erreur de validation JSON
            log_warning "Problème de format JSON détecté"
            ;;
        2) # Erreur de calcul
            log_warning "Erreur dans les calculs d'optimisation"
            ;;
        3) # Erreur d'accès fichier
            log_warning "Problème d'accès aux fichiers de données"
            ;;
        *) # Erreur inconnue
            log_warning "Erreur inconnue détectée"
            ;;
    esac
    
    if [[ -n "$fallback_action" ]]; then
        log_info "Exécution de l'action de repli : $fallback_action"
        eval "$fallback_action"
    fi
    
    return "$error_code"
}

# Validation JSON avec gestion d'erreur
validate_json() {
    local json="$1"
    local error_message="$2"
    
    if ! echo "$json" | jq '.' >/dev/null 2>&1; then
        handle_error 1 "${error_message:-JSON invalide}" "echo '{}'"
        return 1
    fi
    return 0
}

# Calcul du score de confiance avec gestion d'erreur
calculate_confidence_score() {
    local model=$1
    
    # Validation du modèle
    if ! validate_json "$model" "Modèle invalide pour le calcul du score de confiance"; then
        return 1
    fi
    
    # Extraction des métriques clés
    local stability=$(jq -r '.stability_score' <<< "$model")
    local anomaly_count=$(jq -r '(.anomalies.latency_spikes + .anomalies.packet_loss_events + .anomalies.throughput_drops)' <<< "$model")
    local correlation_strength=$(jq -r 'abs(.correlations.mtu_vs_performance)' <<< "$model")
    local data_points=$(jq -r '.optimal_conditions.time_ranges | length' <<< "$model")
    
    # Vérification des valeurs
    if [[ ! "$stability" =~ ^0\.[0-9]+$ ]] || 
       [[ ! "$correlation_strength" =~ ^0\.[0-9]+$ ]] || 
       [[ ! "$data_points" =~ ^[0-9]+$ ]]; then
        handle_error 2 "Valeurs invalides pour le calcul du score de confiance" "echo '0.0000'"
        return 1
    fi
    
    # Calcul des composants du score
    local stability_weight=0.4
    local anomaly_weight=0.3
    local correlation_weight=0.2
    local data_weight=0.1
    
    # Score de stabilité (déjà entre 0 et 1)
    local stability_score=$stability
    
    # Score d'anomalie (inversé et normalisé)
    local anomaly_score
    if (( anomaly_count > 10 )); then
        anomaly_score=0
    else
        anomaly_score=$(echo "scale=4; 1 - ($anomaly_count / 10)" | bc)
    fi
    
    # Score de corrélation (déjà entre 0 et 1)
    local correlation_score=$correlation_strength
    
    # Score de données
    local data_score
    if (( data_points >= 10 )); then
        data_score=1.0
    else
        data_score=$(echo "scale=4; $data_points/10" | bc)
    fi
    
    # Calcul du score final pondéré
    local confidence
    confidence=$(echo "scale=4; 
        $stability_score * $stability_weight +
        $anomaly_score * $anomaly_weight +
        $correlation_score * $correlation_weight +
        $data_score * $data_weight" | bc)
    
    # Limiter à 1.0 maximum et formater avec 4 décimales
    if (( $(echo "$confidence > 1" | bc -l) )); then
        echo "1.0000"
    else
        printf "%.4f" "$confidence"
    fi
}

# Prédiction des performances avec gestion d'erreur
predict_performance() {
    local interface=$1
    local current_mtu=$2
    
    # Chargement du modèle
    local model
    if ! model=$(jq --arg interface "$interface" '.network_conditions[$interface]' "$MODELS_FILE" 2>/dev/null); then
        handle_error 3 "Erreur lors de la lecture du fichier modèle" "echo '{}'"
        return 1
    fi
    
    # Vérification que le modèle existe
    if [[ -z "$model" || "$model" == "null" ]]; then
        handle_error 1 "Aucun modèle trouvé pour l'interface $interface" "echo '{}'"
        return 1
    fi
    
    # Validation du modèle
    if ! validate_json "$model" "Modèle invalide pour la prédiction des performances"; then
        return 1
    fi
    
    # Extraction des métriques
    local latency_trend=$(jq -r '.latency_trend.trend' <<< "$model")
    local throughput_trend=$(jq -r '.throughput_trend.trend' <<< "$model")
    local packet_loss_trend=$(jq -r '.packet_loss_trend.trend' <<< "$model")
    local optimal_mtu=$(jq -r '.optimal_conditions.mtu' <<< "$model")
    local stability=$(jq -r '.stability_score' <<< "$model")
    local confidence=$(calculate_confidence_score "$model")
    
    # Prédiction des performances futures
    local predictions=$(cat << EOF
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
            "mtu_adjustment": $([ $current_mtu -lt $optimal_mtu ] && echo "increase" || echo "decrease"),
            "expected_improvement": $(echo "scale=4; (1 - abs($current_mtu - $optimal_mtu)/$optimal_mtu) * $confidence" | bc),
            "risk_level": $([ $(echo "$confidence >= 0.8" | bc -l) -eq 1 ] && echo "low" || echo "medium")
        }
    }
}
EOF
)
    
    # Validation des prédictions
    if ! validate_json "$predictions" "Prédictions invalides générées"; then
        return 1
    fi
    
    if ! echo "$predictions" > "$PREDICTIONS_FILE"; then
        handle_error 3 "Erreur lors de l'écriture des prédictions" "true"
        return 1
    fi
    
    echo "$predictions"
}

# Optimisation auto-adaptative avec gestion d'erreur
auto_adapt_mtu() {
    local interface=$1
    local current_mtu=$2
    local new_mtu
    
    # Prédiction des performances
    local predictions
    if ! predictions=$(predict_performance "$interface" "$current_mtu"); then
        log_error "Échec de la prédiction des performances"
        return "$current_mtu"
    fi
    
    # Analyse des prédictions
    local confidence optimal_min optimal_max risk_level expected_improvement
    confidence=$(jq -r '.predictions.confidence_score' <<< "$predictions")
    optimal_min=$(jq -r '.predictions.optimal_mtu_range.min' <<< "$predictions")
    optimal_max=$(jq -r '.predictions.optimal_mtu_range.max' <<< "$predictions")
    risk_level=$(jq -r '.predictions.recommendations.risk_level' <<< "$predictions")
    expected_improvement=$(jq -r '.predictions.recommendations.expected_improvement' <<< "$predictions")
    
    log_info "Confiance=$confidence, optimal_min=$optimal_min, optimal_max=$optimal_max, risk=$risk_level, improvement=$expected_improvement"
    
    # Décision d'ajustement basée sur le niveau de risque et l'amélioration attendue
    if [[ "$risk_level" == "low" && $(echo "$expected_improvement >= 0.1" | bc -l) -eq 1 ]]; then
        if (( current_mtu < optimal_min )); then
            log_info "MTU trop bas, augmentation agressive"
            new_mtu=$((current_mtu + 40))
        elif (( current_mtu > optimal_max )); then
            log_info "MTU trop haut, diminution agressive"
            new_mtu=$((current_mtu - 40))
        else
            log_info "MTU dans la plage optimale"
            new_mtu=$current_mtu
        fi
    elif [[ "$risk_level" == "medium" && $(echo "$expected_improvement >= 0.2" | bc -l) -eq 1 ]]; then
        if (( current_mtu < optimal_min )); then
            log_info "MTU trop bas, augmentation conservative"
            new_mtu=$((current_mtu + 20))
        elif (( current_mtu > optimal_max )); then
            log_info "MTU trop haut, diminution conservative"
            new_mtu=$((current_mtu - 20))
        else
            log_info "MTU proche de l'optimal, ajustement fin"
            new_mtu=$((current_mtu + (optimal_min + optimal_max) / 2 - current_mtu))
        fi
    else
        log_info "Risque élevé ou amélioration insuffisante, maintien du MTU actuel"
        new_mtu=$current_mtu
    fi
    
    # Vérification des limites
    if (( new_mtu > 1500 )); then
        log_warning "MTU ajusté dépassant la limite maximale"
        new_mtu=1500
    elif (( new_mtu < 1280 )); then
        log_warning "MTU ajusté inférieur à la limite minimale"
        new_mtu=1280
    fi
    
    echo "$new_mtu"
}

# Évaluation continue des performances
continuous_evaluation() {
    local interface=$1
    local evaluation_interval=300  # 5 minutes
    local adaptation_threshold=3   # Nombre minimum d'évaluations avant adaptation
    local evaluation_count=0
    
    while true; do
        # Collecte des métriques
        local metrics_file=$(collect_current_metrics "$interface")
        
        # Enregistrement des données
        record_performance_data "$interface" "$metrics_file"
        
        # Analyse des patterns
        analyze_performance_patterns "$interface"
        
        # Incrémentation du compteur d'évaluation
        ((evaluation_count++))
        
        # Optimisation si suffisamment de données collectées
        if (( evaluation_count >= adaptation_threshold )); then
            local current_mtu=$(ip link show "$interface" | grep -oP 'mtu \K\d+')
            local optimal_mtu=$(auto_adapt_mtu "$interface" "$current_mtu")
            
            if [[ "$optimal_mtu" != "$current_mtu" ]]; then
                log_info "Auto-adaptation du MTU : $current_mtu -> $optimal_mtu"
                if update_wireguard_mtu "/etc/wireguard/${interface}.conf" "$optimal_mtu"; then
                    log_info "MTU mis à jour avec succès"
                    evaluation_count=0  # Réinitialisation du compteur après adaptation
                else
                    log_error "Échec de la mise à jour du MTU"
                fi
            fi
        fi
        
        sleep "$evaluation_interval"
    done
}

# Export des fonctions
export -f init_learning_system
export -f record_performance_data
export -f analyze_performance_patterns
export -f predict_performance
export -f calculate_confidence_score
export -f auto_adapt_mtu
export -f continuous_evaluation
export -f log_error
export -f log_warning
export -f log_info
export -f handle_error
export -f validate_json 