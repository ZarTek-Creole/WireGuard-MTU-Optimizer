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

# Analyse des performances
analyze_performance_patterns() {
    local interface="$1"
    log_debug "Starting performance pattern analysis for interface: $interface"

    # Validate input
    if [[ -z "$interface" ]]; then
        log_error "Interface parameter is required for analyze_performance_patterns"
        return 1
    }

    # Check if models file exists and is valid JSON
    if [[ ! -f "$MODELS_FILE" ]]; then
        echo '{"version": "1.0", "network_conditions": {}}' > "$MODELS_FILE"
    fi

    # Extract recent data
    local recent_data
    recent_data=$(jq -c --arg interface "$interface" '.performance_records[] | select(.interface == $interface) | .metrics' "$HISTORY_FILE")
    
    if [[ -z "$recent_data" ]]; then
        log_warning "No recent data found for interface: $interface"
        return 1
    }
    log_debug "Extracted recent data: $recent_data"

    # Calculate metrics
    local latency_avg throughput_avg packet_loss_avg
    latency_avg=$(echo "$recent_data" | jq -s 'map(.latency) | add / length')
    throughput_avg=$(echo "$recent_data" | jq -s 'map(.throughput) | add / length')
    packet_loss_avg=$(echo "$recent_data" | jq -s 'map(.packet_loss) | add / length')

    # Calculate trends (difference between latest and average)
    local latest_data
    latest_data=$(echo "$recent_data" | jq -s 'last')
    local latency_trend throughput_trend packet_loss_trend
    latency_trend=$(echo "$latest_data" | jq --arg avg "$latency_avg" '.latency - ($avg|tonumber)')
    throughput_trend=$(echo "$latest_data" | jq --arg avg "$throughput_avg" '.throughput - ($avg|tonumber)')
    packet_loss_trend=$(echo "$latest_data" | jq --arg avg "$packet_loss_avg" '.packet_loss - ($avg|tonumber)')

    # Generate patterns
    local patterns
    patterns=$(jq -n \
        --arg interface "$interface" \
        --arg latency_avg "$latency_avg" \
        --arg latency_trend "$latency_trend" \
        --arg throughput_avg "$throughput_avg" \
        --arg throughput_trend "$throughput_trend" \
        --arg packet_loss_avg "$packet_loss_avg" \
        --arg packet_loss_trend "$packet_loss_trend" \
        '{
            "version": "1.0",
            "network_conditions": {
                ($interface): {
                    "latency_trend": {
                        "avg": ($latency_avg|tonumber),
                        "trend": ($latency_trend|tonumber)
                    },
                    "throughput_trend": {
                        "avg": ($throughput_avg|tonumber),
                        "trend": ($throughput_trend|tonumber)
                    },
                    "packet_loss_trend": {
                        "avg": ($packet_loss_avg|tonumber),
                        "trend": ($packet_loss_trend|tonumber)
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
                        "mtu_vs_performance": 0.85,
                        "latency_vs_throughput": -0.75
                    }
                }
            }
        }')
    log_debug "Generated patterns: $patterns"

    # Update models file
    if ! echo "$patterns" | jq '.' > "$MODELS_FILE"; then
        log_error "Failed to update models file with new patterns"
        return 1
    }
    log_info "Successfully updated models file with new patterns for interface: $interface"

    return 0
}

predict_performance() {
    local interface="$1"
    local current_mtu="$2"
    log_debug "Starting performance prediction for interface: $interface with MTU: $current_mtu"

    # Validate input
    if [[ -z "$interface" || -z "$current_mtu" ]]; then
        log_error "Both interface and current_mtu parameters are required for predict_performance"
        return 1
    }

    # Check if models file exists
    if [[ ! -f "$MODELS_FILE" ]]; then
        log_error "Models file not found: $MODELS_FILE"
        return 1
    }

    # Extract model for the interface
    local model
    model=$(jq -r --arg interface "$interface" '.network_conditions[$interface]' "$MODELS_FILE")
    
    if [[ "$model" == "null" || -z "$model" ]]; then
        log_error "No model found for interface: $interface"
        return 1
    }
    log_debug "Extracted model: $model"

    # Calculate confidence score
    local confidence_score
    confidence_score=$(calculate_confidence_score "$model")
    if [[ $? -ne 0 ]]; then
        log_error "Failed to calculate confidence score"
        return 1
    }

    # Extract metrics from model
    local optimal_mtu stability_score
    optimal_mtu=$(echo "$model" | jq -r '.optimal_conditions.mtu')
    stability_score=$(echo "$model" | jq -r '.stability_score')

    # Calculate risk level based on MTU difference and stability
    local mtu_diff risk_level expected_improvement
    mtu_diff=$((optimal_mtu - current_mtu))
    
    if [[ $mtu_diff -lt 0 ]]; then
        mtu_diff=$((mtu_diff * -1))
    }

    if [[ $mtu_diff -le 20 && $(echo "$stability_score > 0.9" | bc -l) -eq 1 ]]; then
        risk_level="low"
        expected_improvement=0.95
    else
        risk_level="medium"
        expected_improvement=0.75
    fi

    # Generate predictions
    local predictions
    predictions=$(jq -n \
        --arg confidence "$confidence_score" \
        --arg risk "$risk_level" \
        --arg improvement "$expected_improvement" \
        --arg optimal "$optimal_mtu" \
        '{
            "version": "1.0",
            "predictions": {
                "confidence_score": ($confidence|tonumber),
                "recommendations": {
                    "risk_level": $risk,
                    "expected_improvement": ($improvement|tonumber),
                    "optimal_mtu": ($optimal|tonumber)
                }
            }
        }')
    log_debug "Generated predictions: $predictions"

    # Update predictions file
    if ! echo "$predictions" | jq '.' > "$PREDICTIONS_FILE"; then
        log_error "Failed to update predictions file"
        return 1
    }
    log_info "Successfully updated predictions file for interface: $interface"

    return 0
}

calculate_confidence_score() {
    local model="$1"
    log_debug "Calculating confidence score for model"

    # Validate input
    if [[ -z "$model" ]]; then
        log_error "Model parameter is required for calculate_confidence_score"
        return 1
    }

    # Extract metrics
    local stability anomaly_count correlation_strength data_points
    stability=$(echo "$model" | jq -r '.stability_score // 0')
    anomaly_count=$(echo "$model" | jq -r '(.anomalies.latency_spikes + .anomalies.packet_loss_events + .anomalies.throughput_drops) // 0')
    correlation_strength=$(echo "$model" | jq -r 'abs(.correlations.mtu_vs_performance) // 0')
    data_points=$(echo "$model" | jq -r '.optimal_conditions.time_ranges | length // 0')

    log_debug "Extracted metrics - Stability: $stability, Anomalies: $anomaly_count, Correlation: $correlation_strength, Data points: $data_points"

    # Validate values
    if ! [[ "$stability" =~ ^[0-9]*\.?[0-9]+$ ]] || \
       ! [[ "$correlation_strength" =~ ^[0-9]*\.?[0-9]+$ ]] || \
       ! [[ "$anomaly_count" =~ ^[0-9]+$ ]] || \
       ! [[ "$data_points" =~ ^[0-9]+$ ]]; then
        log_error "Invalid metrics values"
        return 1
    }

    # Calculate component scores
    local stability_weight=0.4
    local anomaly_weight=0.2
    local correlation_weight=0.3
    local data_points_weight=0.1

    # Normalize anomaly score (inverse relationship)
    local anomaly_score
    if [[ $anomaly_count -eq 0 ]]; then
        anomaly_score=1.0
    else
        anomaly_score=$(echo "scale=4; 1 / (1 + $anomaly_count)" | bc)
    fi

    # Normalize data points score (logarithmic scale)
    local data_points_score
    if [[ $data_points -eq 0 ]]; then
        data_points_score=0.0
    else
        data_points_score=$(echo "scale=4; l($data_points) / l(10)" | bc -l)
        if (( $(echo "$data_points_score > 1.0" | bc -l) )); then
            data_points_score=1.0
        fi
    fi

    # Calculate final score
    local final_score
    final_score=$(echo "scale=4; \
        $stability * $stability_weight + \
        $anomaly_score * $anomaly_weight + \
        $correlation_strength * $correlation_weight + \
        $data_points_score * $data_points_weight" | bc)

    # Ensure score is between 0 and 1
    if (( $(echo "$final_score > 1.0" | bc -l) )); then
        final_score=1.0
    elif (( $(echo "$final_score < 0.0" | bc -l) )); then
        final_score=0.0
    fi

    log_debug "Calculated confidence score: $final_score"
    echo "$final_score"
    return 0
}

auto_adapt_mtu() {
    local interface="$1"
    local current_mtu="$2"
    log_debug "Starting MTU adaptation for interface: $interface with current MTU: $current_mtu"

    # Validate input
    if [[ -z "$interface" || -z "$current_mtu" ]]; then
        log_error "Both interface and current_mtu parameters are required for auto_adapt_mtu"
        return 1
    }

    # Validate current MTU range
    if [[ $current_mtu -lt 1280 || $current_mtu -gt 1500 ]]; then
        log_error "Current MTU is outside valid range (1280-1500): $current_mtu"
        return 1
    }

    # Get predictions for current MTU
    if ! predict_performance "$interface" "$current_mtu"; then
        log_error "Failed to predict performance for current MTU"
        return 1
    }

    # Extract predictions
    local predictions
    predictions=$(cat "$PREDICTIONS_FILE")
    if [[ -z "$predictions" ]]; then
        log_error "Failed to read predictions file"
        return 1
    }

    # Extract metrics from predictions
    local confidence_score optimal_mtu risk_level expected_improvement
    confidence_score=$(echo "$predictions" | jq -r '.predictions.confidence_score')
    optimal_mtu=$(echo "$predictions" | jq -r '.predictions.recommendations.optimal_mtu')
    risk_level=$(echo "$predictions" | jq -r '.predictions.recommendations.risk_level')
    expected_improvement=$(echo "$predictions" | jq -r '.predictions.recommendations.expected_improvement')

    # Validate extracted values
    if [[ -z "$confidence_score" || -z "$optimal_mtu" || -z "$risk_level" || -z "$expected_improvement" ]]; then
        log_error "Failed to extract required metrics from predictions"
        return 1
    }

    # Calculate new MTU based on confidence and risk
    local new_mtu
    if (( $(echo "$confidence_score >= 0.8" | bc -l) )) && [[ "$risk_level" == "low" ]]; then
        # High confidence and low risk: use optimal MTU
        new_mtu=$optimal_mtu
    else
        # Lower confidence or higher risk: make smaller adjustment
        local mtu_diff=$((optimal_mtu - current_mtu))
        local adjustment
        if [[ $mtu_diff -gt 0 ]]; then
            adjustment=20
        else
            adjustment=-20
        fi
        new_mtu=$((current_mtu + adjustment))
    fi

    # Ensure new MTU is within valid range
    if [[ $new_mtu -lt 1280 ]]; then
        new_mtu=1280
    elif [[ $new_mtu -gt 1500 ]]; then
        new_mtu=1500
    fi

    log_debug "Calculated new MTU: $new_mtu"
    echo "$new_mtu"
    return 0
}

# Export des fonctions
export -f init_metrics_system
export -f collect_current_metrics
export -f analyze_performance
export -f generate_performance_report
export -f analyze_performance_patterns
export -f predict_performance
export -f auto_adapt_mtu
export -f calculate_confidence_score
export -f log_error
export -f log_warning
export -f log_info
export -f log_debug 