#!/usr/bin/env bats

load '../test_helper'
load '../../wireguard-mtu-tune.sh'

# Configuration pour les tests
setup() {
    export TEMP_DIR=$(mktemp -d)
    export TEST_INTERFACE="wg0"
    export TEST_SERVER="10.0.0.1"
    export TEST_CONFIG="${TEMP_DIR}/wg0.conf"
    
    # Création d'une configuration de test
    cat << EOF > "$TEST_CONFIG"
[Interface]
PrivateKey = private_key_here
Address = 10.0.0.2/24
ListenPort = 51820
MTU = 1420

[Peer]
PublicKey = peer_public_key
Endpoint = ${TEST_SERVER}:51820
AllowedIPs = 10.0.0.0/24
PersistentKeepalive = 25
EOF
    
    chmod 600 "$TEST_CONFIG"
}

# Test du workflow complet
@test "Integration - Workflow complet d'optimisation" {
    # 1. Détection de l'interface
    run detect_interface
    [ "$status" -eq 0 ]
    
    # 2. Configuration système
    run configure_system_parameters "$TEST_INTERFACE"
    [ "$status" -eq 0 ]
    
    # 3. Vérification des paramètres
    run verify_system_parameters "$TEST_INTERFACE"
    [ "$status" -eq 0 ]
    
    # 4. Sauvegarde de la configuration
    run backup_wireguard_config "$TEST_CONFIG" "${TEMP_DIR}/backups"
    [ "$status" -eq 0 ]
    [ -d "${TEMP_DIR}/backups" ]
    
    # 5. Test de performance initial
    run monitor_performance "$TEST_INTERFACE"
    [ "$status" -eq 0 ]
    [ -f "${TEMP_DIR}/performance_stats" ]
    
    # 6. Optimisation auto-adaptative
    run auto_adapt_parameters "$TEST_INTERFACE"
    [ "$status" -eq 0 ]
    
    # 7. Vérification des résultats
    [ -f "${TEMP_DIR}/performance_analysis" ]
    [ -f "${TEMP_DIR}/optimization_recommendations" ]
}

# Test de récupération après erreur
@test "Integration - Récupération après erreur" {
    # 1. Simulation d'une configuration invalide
    echo "Invalid config" > "$TEST_CONFIG"
    
    # 2. Tentative de lecture
    run read_wireguard_config "$TEST_CONFIG"
    [ "$status" -eq 1 ]
    
    # 3. Restauration depuis la sauvegarde
    run restore_wireguard_config "${TEMP_DIR}/backups/*/wg0.conf" "$TEST_CONFIG"
    [ "$status" -eq 0 ]
    
    # 4. Vérification de la restauration
    run validate_wireguard_config "$TEST_CONFIG"
    [ "$status" -eq 0 ]
}

# Test de monitoring continu
@test "Integration - Monitoring continu" {
    # 1. Démarrage du monitoring
    run monitor_performance "$TEST_INTERFACE" &
    local monitor_pid=$!
    
    # 2. Attente et vérification
    sleep 10
    kill $monitor_pid
    
    # 3. Vérification des fichiers de données
    [ -f "${TEMP_DIR}/performance_stats" ]
    [ -f "${TEMP_DIR}/performance_analysis" ]
    
    # 4. Vérification du contenu
    run analyze_performance_data "${TEMP_DIR}/performance_stats"
    [ "$status" -eq 0 ]
}

# Test des conditions réseau dégradées
@test "Integration - Conditions réseau dégradées" {
    # 1. Simulation de conditions dégradées
    tc qdisc add dev "$TEST_INTERFACE" root netem delay 100ms loss 5%
    
    # 2. Test d'optimisation
    run auto_adapt_parameters "$TEST_INTERFACE"
    [ "$status" -eq 0 ]
    
    # 3. Vérification de l'adaptation
    local new_mtu=$(ip link show "$TEST_INTERFACE" | grep -oP 'mtu \K\d+')
    [ "$new_mtu" -lt 1500 ]
    
    # 4. Nettoyage
    tc qdisc del dev "$TEST_INTERFACE" root
}

# Test de charge
@test "Integration - Test sous charge" {
    # 1. Génération de charge réseau
    iperf3 -c "$TEST_SERVER" -t 30 -P 4 &
    local iperf_pid=$!
    
    # 2. Monitoring pendant la charge
    run monitor_performance "$TEST_INTERFACE"
    [ "$status" -eq 0 ]
    
    # 3. Vérification des métriques
    [ -f "${TEMP_DIR}/performance_stats" ]
    
    # 4. Nettoyage
    kill $iperf_pid
}

# Test de cohérence des données
@test "Integration - Cohérence des données" {
    # 1. Collecte initiale
    run collect_current_metrics "$TEST_INTERFACE"
    local initial_metrics="$output"
    
    # 2. Analyse des tendances
    run analyze_performance_trends "$initial_metrics"
    [ "$status" -eq 0 ]
    
    # 3. Vérification des recommandations
    run generate_optimization_recommendations "${TEMP_DIR}/performance_trends"
    [ "$status" -eq 0 ]
    
    # 4. Validation de la cohérence
    [[ -f "${TEMP_DIR}/performance_trends" ]]
    [[ -f "${TEMP_DIR}/optimization_recommendations" ]]
}

# Nettoyage global
teardown() {
    if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
    fi
} 