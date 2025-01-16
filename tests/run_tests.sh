#!/bin/bash

# Configuration
TESTS_DIR=$(dirname "$0")
REPORT_DIR="${TESTS_DIR}/reports"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
REPORT_FILE="${REPORT_DIR}/test_report_${TIMESTAMP}.txt"
JUNIT_REPORT="${REPORT_DIR}/junit_${TIMESTAMP}.xml"
ERROR_LOG="${REPORT_DIR}/errors_${TIMESTAMP}.log"

# Couleurs pour l'affichage
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Création des répertoires nécessaires
mkdir -p "$REPORT_DIR"

# Initialisation des compteurs
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
SKIPPED_TESTS=0

# Fonction de logging
log_message() {
    local level=$1
    local message=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a "$REPORT_FILE"
}

# Vérification des prérequis
check_prerequisites() {
    log_message "INFO" "Vérification des prérequis..."
    
    # Vérification de bats
    if ! command -v bats &>/dev/null; then
        log_message "ERROR" "bats n'est pas installé"
        exit 1
    fi
    
    # Vérification des permissions root
    if [[ $EUID -ne 0 ]]; then
        log_message "ERROR" "Ce script doit être exécuté en tant que root"
        exit 1
    fi
    
    # Chargement des fonctions d'aide
    if [[ ! -f "${TESTS_DIR}/test_helper.bash" ]]; then
        log_message "ERROR" "Fichier test_helper.bash non trouvé"
        exit 1
    fi
    
    source "${TESTS_DIR}/test_helper.bash"
    
    # Vérification des outils requis
    if ! check_required_tools; then
        log_message "ERROR" "Outils requis manquants"
        exit 1
    fi
}

# Exécution des tests unitaires
run_unit_tests() {
    log_message "INFO" "Exécution des tests unitaires..."
    
    local unit_tests_dir="${TESTS_DIR}/unit"
    if [[ ! -d "$unit_tests_dir" ]]; then
        log_message "ERROR" "Répertoire des tests unitaires non trouvé"
        return 1
    fi
    
    for test_file in "${unit_tests_dir}"/*.bats; do
        if [[ -f "$test_file" ]]; then
            log_message "INFO" "Exécution de ${test_file}..."
            if bats --tap "$test_file" | tee -a "$REPORT_FILE"; then
                ((PASSED_TESTS++))
            else
                ((FAILED_TESTS++))
                echo "Échec du test : ${test_file}" >> "$ERROR_LOG"
            fi
            ((TOTAL_TESTS++))
        fi
    done
}

# Exécution des tests d'intégration
run_integration_tests() {
    log_message "INFO" "Exécution des tests d'intégration..."
    
    local integration_tests_dir="${TESTS_DIR}/integration"
    if [[ ! -d "$integration_tests_dir" ]]; then
        log_message "ERROR" "Répertoire des tests d'intégration non trouvé"
        return 1
    fi
    
    # Configuration de l'environnement de test
    setup_test_environment
    
    for test_file in "${integration_tests_dir}"/*.bats; do
        if [[ -f "$test_file" ]]; then
            log_message "INFO" "Exécution de ${test_file}..."
            if bats --tap "$test_file" | tee -a "$REPORT_FILE"; then
                ((PASSED_TESTS++))
            else
                ((FAILED_TESTS++))
                echo "Échec du test : ${test_file}" >> "$ERROR_LOG"
            fi
            ((TOTAL_TESTS++))
        fi
    done
    
    # Nettoyage
    cleanup_test_environment
}

# Génération du rapport JUnit
generate_junit_report() {
    cat << EOF > "$JUNIT_REPORT"
<?xml version="1.0" encoding="UTF-8"?>
<testsuites>
    <testsuite name="WireGuard MTU Optimizer Tests" tests="${TOTAL_TESTS}" failures="${FAILED_TESTS}" skipped="${SKIPPED_TESTS}">
        <properties>
            <property name="timestamp" value="$(date -Iseconds)"/>
        </properties>
EOF
    
    # Ajout des résultats de test
    while IFS= read -r line; do
        if [[ "$line" =~ ^ok|^not\ ok ]]; then
            local status="${line%% *}"
            local name="${line#* # }"
            echo "        <testcase name=\"${name}\">" >> "$JUNIT_REPORT"
            if [[ "$status" == "not" ]]; then
                echo "            <failure message=\"Test failed\"/>" >> "$JUNIT_REPORT"
            fi
            echo "        </testcase>" >> "$JUNIT_REPORT"
        fi
    done < "$REPORT_FILE"
    
    echo "    </testsuite>" >> "$JUNIT_REPORT"
    echo "</testsuites>" >> "$JUNIT_REPORT"
}

# Affichage du résumé
show_summary() {
    echo -e "\n${YELLOW}Résumé des Tests${NC}"
    echo "===================="
    echo -e "Total des tests    : ${TOTAL_TESTS}"
    echo -e "Tests réussis      : ${GREEN}${PASSED_TESTS}${NC}"
    echo -e "Tests échoués      : ${RED}${FAILED_TESTS}${NC}"
    echo -e "Tests ignorés      : ${YELLOW}${SKIPPED_TESTS}${NC}"
    
    if [[ $FAILED_TESTS -gt 0 ]]; then
        echo -e "\n${RED}Erreurs détectées${NC}"
        echo "=================="
        cat "$ERROR_LOG"
    fi
    
    echo -e "\nRapports générés :"
    echo "- Rapport détaillé : $REPORT_FILE"
    echo "- Rapport JUnit    : $JUNIT_REPORT"
    echo "- Log d'erreurs    : $ERROR_LOG"
}

# Fonction principale
main() {
    log_message "INFO" "Démarrage des tests..."
    
    # Vérification des prérequis
    check_prerequisites
    
    # Exécution des tests
    run_unit_tests
    run_integration_tests
    
    # Génération des rapports
    generate_junit_report
    
    # Affichage du résumé
    show_summary
    
    # Retourne le statut global
    [[ $FAILED_TESTS -eq 0 ]]
}

# Exécution du script
main "$@" 