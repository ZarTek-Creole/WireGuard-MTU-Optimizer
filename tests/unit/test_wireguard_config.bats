#!/usr/bin/env bats

load '../../wireguard-mtu-tune.sh'

# Tests de lecture de configuration
@test "Lecture configuration WireGuard - Fichier valide" {
    local config_file="${BATS_TMPDIR}/wg0.conf"
    cat << EOF > "$config_file"
[Interface]
PrivateKey = private_key_here
Address = 10.0.0.1/24
ListenPort = 51820
MTU = 1420

[Peer]
PublicKey = peer_public_key
Endpoint = peer.example.com:51820
AllowedIPs = 10.0.0.0/24
PersistentKeepalive = 25
EOF
    
    run read_wireguard_config "$config_file"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "MTU = 1420" ]]
}

@test "Lecture configuration WireGuard - Fichier invalide" {
    local config_file="${BATS_TMPDIR}/invalid.conf"
    echo "Invalid config" > "$config_file"
    
    run read_wireguard_config "$config_file"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Configuration invalide" ]]
}

# Tests de sauvegarde de configuration
@test "Sauvegarde configuration WireGuard" {
    local config_file="${BATS_TMPDIR}/wg0.conf"
    local backup_dir="${BATS_TMPDIR}/backups"
    
    run backup_wireguard_config "$config_file" "$backup_dir"
    [ "$status" -eq 0 ]
    [ -d "$backup_dir" ]
}

# Tests de validation de configuration
@test "Validation configuration WireGuard - MTU valide" {
    local config_file="${BATS_TMPDIR}/wg0.conf"
    cat << EOF > "$config_file"
[Interface]
MTU = 1420
EOF
    
    run validate_wireguard_config "$config_file"
    [ "$status" -eq 0 ]
}

@test "Validation configuration WireGuard - MTU invalide" {
    local config_file="${BATS_TMPDIR}/wg0.conf"
    cat << EOF > "$config_file"
[Interface]
MTU = 1000
EOF
    
    run validate_wireguard_config "$config_file"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "MTU invalide" ]]
}

# Tests de mise à jour de configuration
@test "Mise à jour MTU WireGuard" {
    local config_file="${BATS_TMPDIR}/wg0.conf"
    cat << EOF > "$config_file"
[Interface]
MTU = 1420
EOF
    
    run update_wireguard_mtu "$config_file" 1400
    [ "$status" -eq 0 ]
    [[ $(grep "MTU = 1400" "$config_file") ]]
}

# Tests de permissions
@test "Vérification permissions fichier WireGuard" {
    local config_file="${BATS_TMPDIR}/wg0.conf"
    touch "$config_file"
    chmod 600 "$config_file"
    
    run check_wireguard_permissions "$config_file"
    [ "$status" -eq 0 ]
}

@test "Vérification permissions fichier WireGuard - Trop permissif" {
    local config_file="${BATS_TMPDIR}/wg0.conf"
    touch "$config_file"
    chmod 644 "$config_file"
    
    run check_wireguard_permissions "$config_file"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Permissions trop permissives" ]]
}

# Tests de cohérence de configuration
@test "Vérification cohérence configuration WireGuard" {
    local config_file="${BATS_TMPDIR}/wg0.conf"
    cat << EOF > "$config_file"
[Interface]
PrivateKey = private_key_here
Address = 10.0.0.1/24
ListenPort = 51820
MTU = 1420

[Peer]
PublicKey = peer_public_key
Endpoint = peer.example.com:51820
AllowedIPs = 10.0.0.0/24
PersistentKeepalive = 25
EOF
    
    run check_wireguard_config_coherence "$config_file"
    [ "$status" -eq 0 ]
}

# Tests de restauration
@test "Restauration configuration WireGuard" {
    local config_file="${BATS_TMPDIR}/wg0.conf"
    local backup_file="${BATS_TMPDIR}/backups/wg0.conf.bak"
    mkdir -p "${BATS_TMPDIR}/backups"
    
    # Créer une sauvegarde
    cat << EOF > "$backup_file"
[Interface]
MTU = 1420
EOF
    
    run restore_wireguard_config "$backup_file" "$config_file"
    [ "$status" -eq 0 ]
    [ -f "$config_file" ]
    [[ $(grep "MTU = 1420" "$config_file") ]]
} 