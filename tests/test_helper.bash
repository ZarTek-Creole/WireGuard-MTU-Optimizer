#!/usr/bin/env bash

# Fonctions utilitaires pour les tests
setup_test_environment() {
    export TEMP_DIR=$(mktemp -d)
    export TEST_DATA_DIR="${TEMP_DIR}/test_data"
    mkdir -p "$TEST_DATA_DIR"
}

cleanup_test_environment() {
    if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
    fi
}

# Fonction pour créer des fichiers de test
create_test_file() {
    local file_path="$1"
    local content="$2"
    echo "$content" > "$file_path"
}

# Fonction pour vérifier la validité JSON
is_valid_json() {
    local file_path="$1"
    jq '.' "$file_path" >/dev/null 2>&1
    return $?
}

# Export des fonctions
export -f setup_test_environment
export -f cleanup_test_environment
export -f create_test_file
export -f is_valid_json 