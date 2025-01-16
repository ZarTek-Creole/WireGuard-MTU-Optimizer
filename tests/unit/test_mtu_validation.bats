#!/usr/bin/env bats

load '../../wireguard-mtu-tune.sh'

@test "Validation MTU - Valeurs valides normales" {
    run validate_mtu_range 1280 1500
    [ "$status" -eq 0 ]
}

@test "Validation MTU - Valeurs valides limites" {
    run validate_mtu_range 1280 9000
    [ "$status" -eq 0 ]
}

@test "Validation MTU - MIN_MTU trop petit" {
    run validate_mtu_range 1000 1500
    [ "$status" -eq 1 ]
    [[ "$output" =~ "MTU values must be between 1280 and 9000" ]]
}

@test "Validation MTU - MAX_MTU trop grand" {
    run validate_mtu_range 1280 9500
    [ "$status" -eq 1 ]
    [[ "$output" =~ "MTU values must be between 1280 and 9000" ]]
}

@test "Validation MTU - MIN_MTU supérieur à MAX_MTU" {
    run validate_mtu_range 1500 1280
    [ "$status" -eq 1 ]
    [[ "$output" =~ "MIN_MTU must be less than MAX_MTU" ]]
}

@test "Validation MTU - Valeurs égales" {
    run validate_mtu_range 1500 1500
    [ "$status" -eq 1 ]
    [[ "$output" =~ "MIN_MTU must be less than MAX_MTU" ]]
} 