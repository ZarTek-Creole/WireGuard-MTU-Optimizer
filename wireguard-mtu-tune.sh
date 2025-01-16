#!/bin/bash
#
# WireGuard MTU Optimizer (WG-MTU-OPT)
# Version: 1.0.0
#
# Author: ZarTek-Creole (https://github.com/ZarTek-Creole)
# Repository: https://github.com/ZarTek-Creole/WireGuard-MTU-Optimizer
# License: MIT
#
# Description:
#   A sophisticated network optimization tool that automatically discovers and
#   fine-tunes WireGuard MTU settings for optimal performance. The script conducts
#   parallel testing of different MTU values while measuring both latency and
#   throughput to determine the most efficient configuration.
#
# Features:
#   - Automatic WireGuard interface detection
#   - Parallel MTU testing with smart retry logic
#   - Comprehensive performance analysis (latency & throughput)
#   - Detailed logging and real-time monitoring
#   - Resource-aware parallel processing
#   - Automated log rotation
#
# Dependencies:
#   - WireGuard interface
#   - iperf3
#   - parallel
#   - bash 4.0+
#   - Root privileges
#
# Usage:
#   ./wireguard-mtu-tune.sh [-i INTERFACE] [-s SERVER_IP] [-m MIN_MTU] [-n MAX_MTU]
#                          [-p STEP] [-l LOG_FILE] [-j MAX_JOBS] [-v] [-r RETRY_COUNT]
#
# Options:
#   -i INTERFACE   : Specify WireGuard interface (default: auto-detect)
#   -s SERVER_IP   : Server IP for testing (default: 95.216.45.182)
#   -m MIN_MTU     : Minimum MTU value (default: 1280)
#   -n MAX_MTU     : Maximum MTU value (default: 1500)
#   -p STEP        : MTU increment step (default: 10)
#   -l LOG_FILE    : Log file location (default: /tmp/mtu_test.log)
#   -j MAX_JOBS    : Number of parallel jobs (default: CPU cores)
#   -v             : Enable verbose logging
#   -r RETRY_COUNT : Number of retry attempts (default: 3)
#
# Example:
#   sudo ./wireguard-mtu-tune.sh -i wg0 -s 10.0.0.1 -m 1280 -n 1500 -p 10 -v 

# Set strict error handling
set -euo pipefail
IFS=$'\n\t'

# Color definitions for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m' # No Color

# Default configuration values
SERVER_IP="10.66.66.1"
INTERFACE=""
MIN_MTU=1280
MAX_MTU=1500
STEP=10
LOG_FILE="/tmp/mtu_test.log"
MAX_JOBS=$(nproc)
VERBOSITY=1
RETRY_COUNT=3
TEMP_DIR=$(mktemp -d)
LOCK_FILE="${TEMP_DIR}/wg_mtu_lock"

# Enhanced process locking mechanism
acquire_lock() {
    local max_attempts=30
    local attempt=0
    local wait_time=1
    
    while [[ $attempt -lt $max_attempts ]]; do
        if mkdir "${LOCK_FILE}" 2>/dev/null; then
            # Store PID in lock file
            echo $$ > "${LOCK_FILE}/pid"
            log_message "DEBUG" "Lock acquired successfully"
            return 0
        fi
        
        # Check if the lock holder is still alive
        if [[ -f "${LOCK_FILE}/pid" ]]; then
            local lock_pid=$(cat "${LOCK_FILE}/pid")
            if ! kill -0 "$lock_pid" 2>/dev/null; then
                log_message "WARN" "Removing stale lock from dead process $lock_pid"
                rm -rf "${LOCK_FILE}"
                continue
            fi
        fi
        
        ((attempt++))
        log_message "DEBUG" "Lock acquisition attempt $attempt of $max_attempts"
        sleep $wait_time
    done
    
    log_message "ERROR" "Failed to acquire lock after $max_attempts attempts"
    return 1
}

release_lock() {
    if [[ -d "${LOCK_FILE}" ]]; then
        rm -rf "${LOCK_FILE}"
        log_message "DEBUG" "Lock released"
    fi
}

# Enhanced cleanup with error handling
cleanup() {
    local exit_code=$?
    local error_msg=""
    
    case $exit_code in
        0) log_message "INFO" "Cleanup: Normal termination" ;;
        130) error_msg="Interrupted by user" ;;
        *) error_msg="Failed with exit code $exit_code" ;;
    esac
    
    # Ensure interface is restored
    if [[ -n "$INTERFACE" ]]; then
        restore_config || log_message "ERROR" "Failed to restore interface configuration"
    fi
    
    # Release lock if held
    release_lock
    
    # Remove temporary files
    if [[ -d "${TEMP_DIR}" ]]; then
        rm -rf "${TEMP_DIR}" || log_message "ERROR" "Failed to remove temporary directory"
    fi
    
    # Log final status
    if [[ -n "$error_msg" ]]; then
        log_message "ERROR" "Cleanup: $error_msg"
    fi
    
    exit ${exit_code}
}

# Set trap for cleanup
trap cleanup EXIT INT TERM

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}Error: This script must be run as root${NC}" >&2
        exit 1
    fi
}

# Verify all required commands are available
verify_dependencies() {
    local missing_deps=()
    local required_commands=("ip" "iperf3" "parallel" "awk" "ping")

    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_deps+=("$cmd")
        fi
    done

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        echo -e "${RED}Error: Missing required dependencies: ${missing_deps[*]}${NC}" >&2
        echo "Please install the missing dependencies and try again."
        exit 1
    fi
}

# Enhanced log message function with timestamps and colors
log_message() {
    local level=$1
    local message=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local color=""

    case $level in
        "INFO") color=$GREEN ;;
        "DEBUG") [[ $VERBOSITY -lt 2 ]] && return 0; color=$YELLOW ;;
        "ERROR") color=$RED ;;
        *) color=$NC ;;
    esac

    echo -e "${color}[$timestamp] [LOG_$level] $message${NC}" | tee -a "$LOG_FILE"
}

# Improved log rotation with compression
rotate_log() {
    local max_size=$((10 * 1024 * 1024)) # 10MB
    if [[ -f $LOG_FILE ]]; then
        local size=$(stat -f%z "$LOG_FILE" 2>/dev/null || stat -c%s "$LOG_FILE")
        if [[ $size -ge $max_size ]]; then
            local timestamp=$(date +%Y%m%d_%H%M%S)
            gzip -c "$LOG_FILE" > "${LOG_FILE}.${timestamp}.gz"
            : > "$LOG_FILE"
            log_message "INFO" "Log rotated to ${LOG_FILE}.${timestamp}.gz"
        fi
    fi
}

# Function to validate MTU range
validate_mtu_range() {
    if [[ $MIN_MTU -lt 1280 || $MAX_MTU -gt 9000 ]]; then
        log_message "ERROR" "MTU values must be between 1280 and 9000"
        exit 1
    fi
    if [[ $MIN_MTU -ge $MAX_MTU ]]; then
        log_message "ERROR" "MIN_MTU must be less than MAX_MTU"
        exit 1
    fi
}

# Main script execution
main() {
    check_root
    verify_dependencies
    parse_args "$@"
    validate_mtu_range
    rotate_log
    
    if ! detect_interface; then
        log_message "ERROR" "Échec de la détection de l'interface WireGuard"
        exit 1
    fi
    
    # Configuration et vérification des paramètres système
    if ! configure_system_parameters "$INTERFACE"; then
        log_message "ERROR" "Échec de la configuration système"
        exit 1
    fi
    
    if ! verify_system_parameters "$INTERFACE"; then
        log_message "WARN" "Problèmes détectés dans la configuration système"
    fi
    
    # Détection et adaptation aux conditions réseau
    detect_network_conditions "$INTERFACE"
    optimize_test_parameters
    
    log_message "INFO" "Démarrage de l'optimisation MTU pour l'interface: $INTERFACE"
    if ! run_parallel_tests; then
        log_message "ERROR" "Échec de l'optimisation MTU"
        exit 1
    fi
    
    # Analyse statistique
    analyze_statistics "${TEMP_DIR}/final_results"
    
    log_message "INFO" "Optimisation MTU terminée avec succès"
}

# Parse command line arguments
parse_args() {
    while getopts "i:s:m:n:p:l:j:v:r:" opt; do
        case $opt in
            i) INTERFACE=$OPTARG ;;
            s) SERVER_IP=$OPTARG ;;
            m) MIN_MTU=$OPTARG ;;
            n) MAX_MTU=$OPTARG ;;
            p) STEP=$OPTARG ;;
            l) LOG_FILE=$OPTARG ;;
            j) MAX_JOBS=$OPTARG ;;
            v) VERBOSITY=2 ;;
            r) RETRY_COUNT=$OPTARG ;;
            \?) echo "Invalid option: -$OPTARG" >&2; exit 1 ;;
            :) echo "Option -$OPTARG requires an argument" >&2; exit 1 ;;
        esac
    done
}

# Function to detect WireGuard interface
detect_interface() {
    if [[ -z "$INTERFACE" ]]; then
        INTERFACE=$(ip -o link show | grep -i wg | head -n1 | awk -F': ' '{print $2}')
        if [[ -z "$INTERFACE" ]]; then
            log_message "ERROR" "No WireGuard interface detected"
            return 1
        fi
        log_message "INFO" "Auto-detected WireGuard interface: $INTERFACE"
    fi

    # Validate interface exists and is WireGuard
    if ! ip link show "$INTERFACE" 2>/dev/null | grep -q 'wireguard'; then
        log_message "ERROR" "Interface $INTERFACE is not a WireGuard interface"
        return 1
    fi
    return 0
}

# Function to test single MTU value
test_mtu() {
    local mtu=$1
    local retry=0
    local success=false
    local result_file="${TEMP_DIR}/mtu_${mtu}_result"
    local mtu_lock="${TEMP_DIR}/mtu_${mtu}.lock"
    
    # Acquire lock for this MTU test
    if ! acquire_lock; then
        log_message "ERROR" "Failed to acquire lock for MTU $mtu test"
        return 1
    fi
    
    while [[ $retry -lt $RETRY_COUNT && $success == false ]]; do
        log_message "DEBUG" "Testing MTU $mtu (attempt $((retry + 1))/$RETRY_COUNT)"
        
        # Set MTU with proper error handling
        if ! ip link set dev "$INTERFACE" mtu "$mtu" 2>/dev/null; then
            log_message "ERROR" "Failed to set MTU $mtu on interface $INTERFACE"
            release_lock
            return 1
        fi
        
        # Ensure proper timing for interface stability
        sleep 2
        
        # Comprehensive connectivity test
        if ! timeout 5 bash -c "ping -c 1 -W 2 $SERVER_IP >/dev/null 2>&1"; then
            log_message "DEBUG" "MTU $mtu: Connectivity test failed"
            ((retry++))
            continue
        fi
        
        # Enhanced measurements with timeout protection
        local latency=$(timeout 10 ping -c 4 -q "$SERVER_IP" 2>/dev/null | \
            awk -F'/' 'END{print $5}')
        
        local throughput=$(timeout 15 iperf3 -c "$SERVER_IP" -t 5 -f m 2>/dev/null | \
            awk '/receiver/ {print $7}')
        
        if [[ -n "$latency" && -n "$throughput" ]]; then
            echo "${mtu},${latency},${throughput}" > "$result_file"
            success=true
            log_message "INFO" "MTU $mtu: Latency ${latency}ms, Throughput ${throughput}Mbits/sec"
        else
            ((retry++))
        fi
    done
    
    # Release lock before returning
    release_lock
    
    if [[ $success == false ]]; then
        log_message "ERROR" "Failed to test MTU $mtu after $RETRY_COUNT attempts"
        return 1
    fi
    
    return 0
}

# Function to monitor system resources
monitor_resources() {
    local pid=$1
    local stats_file="${TEMP_DIR}/resource_stats"
    
    while kill -0 $pid 2>/dev/null; do
        local cpu=$(ps -p $pid -o %cpu | tail -n1)
        local mem=$(ps -p $pid -o %mem | tail -n1)
        local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        echo "$timestamp,$cpu,$mem" >> "$stats_file"
        sleep 1
    done
}

# Function to validate server connectivity
validate_server() {
    log_message "INFO" "Validating connectivity to server $SERVER_IP..."
    
    # Check if iperf3 server is running
    if ! timeout 5 iperf3 -c "$SERVER_IP" -t 1 >/dev/null 2>&1; then
        log_message "ERROR" "Cannot connect to iperf3 server at $SERVER_IP"
        return 1
    fi
    
    # Verify basic connectivity
    if ! ping -c 1 -W 2 "$SERVER_IP" >/dev/null 2>&1; then
        log_message "ERROR" "Cannot ping server at $SERVER_IP"
        return 1
    }
    
    log_message "INFO" "Server connectivity validated successfully"
    return 0
}

# Function to backup current network configuration
backup_config() {
    local backup_dir="${TEMP_DIR}/backup"
    mkdir -p "$backup_dir"
    
    # Backup interface configuration
    ip link show "$INTERFACE" > "${backup_dir}/interface_config"
    ip addr show "$INTERFACE" > "${backup_dir}/addr_config"
    
    # Backup routing information
    ip route show > "${backup_dir}/route_config"
    
    log_message "INFO" "Network configuration backed up to $backup_dir"
}

# Function to restore network configuration
restore_config() {
    local backup_dir="${TEMP_DIR}/backup"
    if [[ ! -d "$backup_dir" ]]; then
        log_message "ERROR" "Backup directory not found"
        return 1
    }
    
    # Restore original MTU
    local original_mtu=$(awk '/mtu/ {print $5}' "${backup_dir}/interface_config")
    if [[ -n "$original_mtu" ]]; then
        ip link set dev "$INTERFACE" mtu "$original_mtu"
        log_message "INFO" "Restored original MTU: $original_mtu"
    fi
}

# Function to generate performance graphs
generate_graphs() {
    local results_file="$1"
    local output_dir="${LOG_FILE%/*}/graphs"
    mkdir -p "$output_dir"
    
    # Generate graphs using gnuplot
    if command -v gnuplot >/dev/null 2>&1; then
        cat << EOF > "${TEMP_DIR}/plot_script"
set terminal png size 800,600
set output '${output_dir}/mtu_performance.png'
set title 'MTU Performance Analysis'
set xlabel 'MTU Size'
set ylabel 'Score'
plot '${results_file}' using 1:4 with linespoints title 'Performance Score'
EOF
        gnuplot "${TEMP_DIR}/plot_script"
        log_message "INFO" "Performance graphs generated in $output_dir"
    else
        log_message "DEBUG" "gnuplot not available, skipping graph generation"
    fi
}

# Enhanced parallel test execution with resource monitoring
run_parallel_tests() {
    local start_time=$(date +%s)
    
    # Backup current configuration
    backup_config
    
    # Validate server before starting tests
    if ! validate_server; then
        log_message "ERROR" "Server validation failed, aborting tests"
        return 1
    }
    
    log_message "INFO" "Starting parallel MTU tests from $MIN_MTU to $MAX_MTU (step: $STEP)"
    
    # Create sequence of MTU values to test
    seq "$MIN_MTU" "$STEP" "$MAX_MTU" > "${TEMP_DIR}/mtu_values"
    
    # Start resource monitoring in background
    monitor_resources $$ &
    local monitor_pid=$!
    
    # Run tests in parallel with progress tracking
    parallel --progress --jobs "$MAX_JOBS" test_mtu {} < "${TEMP_DIR}/mtu_values"
    local test_status=$?
    
    # Stop resource monitoring
    kill $monitor_pid 2>/dev/null
    
    # Process results only if tests were successful
    if [[ $test_status -eq 0 ]]; then
        process_results
        generate_graphs "${TEMP_DIR}/final_results"
    else
        log_message "ERROR" "Parallel tests failed"
        restore_config
        return 1
    fi
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    log_message "INFO" "MTU optimization completed in ${duration} seconds"
}

# Function to process and analyze results
process_results() {
    log_message "INFO" "Processing test results..."
    
    local best_mtu=""
    local best_score=0
    local results_file="${TEMP_DIR}/final_results"
    
    # Collect all results
    echo "MTU,Latency,Throughput,Score" > "$results_file"
    
    for result in "${TEMP_DIR}"/mtu_*_result; do
        [[ -f "$result" ]] || continue
        
        IFS=',' read -r mtu latency throughput < "$result"
        
        # Calculate score (lower latency and higher throughput is better)
        # Normalize values: latency 0-100ms = 1-0, throughput 0-1000Mbps = 0-1
        local latency_score=$(echo "scale=4; (100 - ($latency < 100 ? $latency : 100)) / 100" | bc)
        local throughput_score=$(echo "scale=4; ($throughput < 1000 ? $throughput : 1000) / 1000" | bc)
        local score=$(echo "scale=4; ($latency_score + $throughput_score) / 2" | bc)
        
        echo "${mtu},${latency},${throughput},${score}" >> "$results_file"
        
        if (( $(echo "$score > $best_score" | bc -l) )); then
            best_score=$score
            best_mtu=$mtu
        fi
    done
    
    # Generate summary report
    generate_report "$best_mtu" "$best_score" "$results_file"
}

# Function to generate final report
generate_report() {
    local best_mtu=$1
    local best_score=$2
    local results_file=$3
    
    log_message "INFO" "Generating optimization report..."
    
    # Create report header
    cat << EOF > "${LOG_FILE}.report"
WireGuard MTU Optimization Report
================================
Interface: $INTERFACE
Date: $(date '+%Y-%m-%d %H:%M:%S')
Test Duration: ${duration} seconds

Optimal Configuration
-------------------
Best MTU: $best_mtu
Score: $best_score

Detailed Results
---------------
$(column -t -s',' "$results_file")

EOF
    
    log_message "INFO" "Report generated: ${LOG_FILE}.report"
    log_message "INFO" "Recommended MTU for $INTERFACE: $best_mtu"
    
    # Apply optimal MTU
    if ip link set dev "$INTERFACE" mtu "$best_mtu"; then
        log_message "INFO" "Successfully applied optimal MTU $best_mtu to $INTERFACE"
    else
        log_message "ERROR" "Failed to apply optimal MTU $best_mtu to $INTERFACE"
    fi
}

# Function to handle interrupts gracefully
handle_interrupt() {
    log_message "INFO" "Received interrupt signal, cleaning up..."
    restore_config
    cleanup
    exit 130
}

# Add interrupt handler
trap handle_interrupt INT

# Function to perform statistical analysis
analyze_statistics() {
    local results_file="$1"
    local stats_file="${TEMP_DIR}/statistics"
    
    # Calculate basic statistics
    awk -F',' '
        NR>1 {
            # Collect data
            mtu[NR]=$1
            latency[NR]=$2
            throughput[NR]=$3
            score[NR]=$4
            
            # Running calculations
            lat_sum+=$2
            tput_sum+=$3
            score_sum+=$4
            
            # Track min/max
            if(NR==2 || $2<min_lat) min_lat=$2
            if(NR==2 || $2>max_lat) max_lat=$2
            if(NR==2 || $3<min_tput) min_tput=$3
            if(NR==2 || $3>max_tput) max_tput=$3
            if(NR==2 || $4<min_score) min_score=$4
            if(NR==2 || $4>max_score) max_score=$4
        }
        END {
            count=NR-1
            
            # Calculate averages
            avg_lat=lat_sum/count
            avg_tput=tput_sum/count
            avg_score=score_sum/count
            
            # Calculate standard deviations
            for(i=2;i<=NR;i++) {
                lat_var+=((latency[i]-avg_lat)^2)
                tput_var+=((throughput[i]-avg_tput)^2)
                score_var+=((score[i]-avg_score)^2)
            }
            lat_std=sqrt(lat_var/count)
            tput_std=sqrt(tput_var/count)
            score_std=sqrt(score_var/count)
            
            # Output statistics
            print "Latency (ms):," avg_lat "," min_lat "," max_lat "," lat_std
            print "Throughput (Mbps):," avg_tput "," min_tput "," max_tput "," tput_std
            print "Score:," avg_score "," min_score "," max_score "," score_std
        }
    ' "$results_file" > "$stats_file"
    
    return 0
}

# Function to analyze TCP window size
analyze_tcp_window() {
    local interface=$1
    local stats_file="${TEMP_DIR}/tcp_analysis"
    
    log_message "INFO" "Analyzing TCP window size optimization..."
    
    # Capture TCP window statistics
    timeout 10 tcpdump -i "$interface" -nn 'tcp[tcpflags] & tcp-syn != 0' 2>/dev/null | \
        awk '{ print $8 }' > "$stats_file"
    
    # Analyze window scaling
    local window_scale=$(ss -i | grep -i "$interface" | awk '/wscale/ {print $4}')
    
    # Record findings
    cat << EOF >> "${LOG_FILE}.tcp_analysis"
TCP Window Analysis
==================
Interface: $interface
Window Scale: $window_scale
Timestamp: $(date '+%Y-%m-%d %H:%M:%S')
EOF
}

# Function to verify Path MTU Discovery
verify_pmtud() {
    local interface=$1
    local target=$2
    local pmtud_file="${TEMP_DIR}/pmtud_verify"
    
    log_message "INFO" "Verifying Path MTU Discovery..."
    
    # Check if PMTUD is enabled
    local pmtud_status=$(sysctl -n net.ipv4.ip_no_pmtu_disc)
    
    # Test with different packet sizes
    for size in 1500 1400 1300 1200; do
        ping -c 1 -M do -s $size "$target" >> "$pmtud_file" 2>&1
    done
    
    # Analyze results
    if grep -q "Message too long" "$pmtud_file"; then
        log_message "INFO" "PMTUD is active and functioning"
        return 0
    else
        log_message "WARN" "PMTUD may be disabled or blocked"
        return 1
    fi
}

# Enhanced network condition detection
detect_network_conditions() {
    local ping_samples=20  # Increased for better accuracy
    local test_file="${TEMP_DIR}/network_conditions"
    local interface=$1
    
    log_message "INFO" "Performing comprehensive network analysis..."
    
    # Advanced latency analysis with percentiles
    local latency_stats=$(ping -c $ping_samples -q "$SERVER_IP" 2>/dev/null | \
        awk -F'/' 'END{print $5","$6","$7}')
    local avg_latency=$(echo "$latency_stats" | cut -d',' -f1)
    local min_latency=$(echo "$latency_stats" | cut -d',' -f2)
    local max_latency=$(echo "$latency_stats" | cut -d',' -f3)
    
    # Enhanced jitter calculation
    local jitter_samples=()
    for i in $(seq 1 $ping_samples); do
        local sample=$(ping -c 1 "$SERVER_IP" | \
            grep -oP 'time=\K[0-9.]+')
        jitter_samples+=($sample)
    done
    
    # Calculate jitter (variance of latency)
    local jitter=0
    local prev=${jitter_samples[0]}
    for sample in "${jitter_samples[@]:1}"; do
        local diff=$(echo "$sample - $prev" | bc)
        jitter=$(echo "$jitter + ${diff#-}" | bc)
        prev=$sample
    done
    jitter=$(echo "scale=3; $jitter / ($ping_samples - 1)" | bc)
    
    # Enhanced packet loss detection
    local packet_loss=$(ping -c $((ping_samples * 2)) -f "$SERVER_IP" 2>&1 | \
        awk -F'[,%]' '/packet loss/ {print $2}')
    
    # Network congestion detection
    local congestion_detected=false
    if [[ $(echo "$avg_latency > 2 * $min_latency" | bc -l) -eq 1 ]]; then
        congestion_detected=true
    fi
    
    # TCP connection analysis
    local tcp_retrans=$(netstat -s | awk '/segments retransmitted/ {print $1}')
    
    # Comprehensive network quality assessment
    local network_quality
    if (( $(echo "$avg_latency < 30" | bc -l) )) && \
       (( $(echo "$jitter < 5" | bc -l) )) && \
       (( $(echo "$packet_loss < 0.1" | bc -l) )) && \
       [[ $congestion_detected == false ]]; then
        network_quality="EXCELLENT"
    elif (( $(echo "$avg_latency < 80" | bc -l) )) && \
         (( $(echo "$jitter < 15" | bc -l) )) && \
         (( $(echo "$packet_loss < 1" | bc -l) )); then
        network_quality="GOOD"
    elif (( $(echo "$avg_latency < 150" | bc -l) )) && \
         (( $(echo "$jitter < 30" | bc -l) )) && \
         (( $(echo "$packet_loss < 5" | bc -l) )); then
        network_quality="FAIR"
    else
        network_quality="POOR"
    fi
    
    # Save comprehensive network analysis
    cat << EOF > "$test_file"
Network Analysis Report
======================
Timestamp: $(date '+%Y-%m-%d %H:%M:%S')
Interface: $interface

Latency Statistics
-----------------
Average: $avg_latency ms
Minimum: $min_latency ms
Maximum: $max_latency ms
Jitter: $jitter ms

Reliability Metrics
------------------
Packet Loss: $packet_loss%
TCP Retransmissions: $tcp_retrans
Congestion Detected: $congestion_detected

Quality Assessment
-----------------
Network Quality: $network_quality

Additional Metrics
-----------------
RTT Variance: $(echo "scale=4; ($max_latency - $min_latency) / $avg_latency" | bc)
Stability Index: $(echo "scale=4; 1 - ($packet_loss / 100)" | bc)
EOF
    
    log_message "INFO" "Comprehensive network analysis completed: $network_quality"
    return 0
}

# Enhanced optimization parameter adjustment
optimize_test_parameters() {
    local network_quality=$(awk '/Network Quality/ {print $3}' "${TEMP_DIR}/network_conditions")
    local packet_loss=$(awk '/Packet Loss/ {print $2}' "${TEMP_DIR}/network_conditions" | tr -d '%')
    local stability_index=$(awk '/Stability Index/ {print $2}' "${TEMP_DIR}/network_conditions")
    
    # Dynamic parameter adjustment based on network conditions
    case $network_quality in
        "EXCELLENT")
            RETRY_COUNT=2
            STEP=5
            MAX_JOBS=$(($(nproc) * 2))
            ;;
        "GOOD")
            RETRY_COUNT=3
            STEP=10
            MAX_JOBS=$(nproc)
            ;;
        "FAIR")
            RETRY_COUNT=4
            STEP=15
            MAX_JOBS=$(($(nproc) / 2))
            ;;
        "POOR")
            RETRY_COUNT=6
            STEP=25
            MAX_JOBS=2
            ;;
    esac
    
    # Additional adjustments based on stability
    if (( $(echo "$stability_index < 0.95" | bc -l) )); then
        RETRY_COUNT=$((RETRY_COUNT + 2))
        MAX_JOBS=$((MAX_JOBS / 2))
    fi
    
    # Adjust test timing based on network conditions
    if (( $(echo "$packet_loss > 2" | bc -l) )); then
        TEST_INTERVAL=5  # Increase interval between tests
    else
        TEST_INTERVAL=2
    fi
    
    log_message "INFO" "Optimized parameters for $network_quality network conditions"
    log_message "DEBUG" "Parameters: Retry=$RETRY_COUNT, Step=$STEP, Jobs=$MAX_JOBS, Interval=$TEST_INTERVAL"
}

# Configuration des paramètres système pour WireGuard
configure_system_parameters() {
    local sysctl_file="/etc/sysctl.d/99-wireguard.conf"
    local interface=$1
    
    log_message "INFO" "Configuration des paramètres système pour WireGuard..."
    
    # Vérification des permissions
    if [[ ! -w "/etc/sysctl.d/" ]]; then
        log_message "ERROR" "Permissions insuffisantes pour /etc/sysctl.d/"
        return 1
    }
    
    # Sauvegarde de la configuration existante
    if [[ -f "$sysctl_file" ]]; then
        cp "$sysctl_file" "${sysctl_file}.backup.$(date +%Y%m%d_%H%M%S)"
        log_message "INFO" "Sauvegarde de la configuration sysctl existante"
    fi
    
    # Paramètres optimaux pour WireGuard
    cat << EOF > "$sysctl_file"
# Paramètres optimisés pour WireGuard
# Généré par WireGuard MTU Optimizer le $(date '+%Y-%m-%d %H:%M:%S')

# Optimisation de la mémoire réseau
net.core.rmem_max = 2500000
net.core.wmem_max = 2500000
net.core.rmem_default = 1000000
net.core.wmem_default = 1000000
net.ipv4.tcp_rmem = 4096 87380 2500000
net.ipv4.tcp_wmem = 4096 87380 2500000

# Optimisation des tampons
net.core.netdev_max_backlog = 5000
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_congestion_control = cubic

# Paramètres de routage et MTU
net.ipv4.ip_forward = 1
net.ipv4.ip_no_pmtu_disc = 0
net.ipv4.tcp_ecn = 1

# Optimisations spécifiques à l'interface
net.ipv4.conf.${interface}.rp_filter = 2
net.ipv4.conf.${interface}.accept_redirects = 0
net.ipv4.conf.${interface}.send_redirects = 0

# Paramètres de performance
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_keepalive_probes = 5
net.ipv4.tcp_keepalive_intvl = 15

# Optimisation de la congestion
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_sack = 1
net.ipv4.tcp_fack = 1
EOF
    
    # Application des paramètres
    if ! sysctl -p "$sysctl_file"; then
        log_message "ERROR" "Échec de l'application des paramètres système"
        return 1
    fi
    
    log_message "INFO" "Paramètres système configurés avec succès"
    return 0
}

# Fonction de vérification des paramètres système
verify_system_parameters() {
    local interface=$1
    local verification_file="${TEMP_DIR}/sysctl_verify"
    
    log_message "INFO" "Vérification des paramètres système..."
    
    # Liste des paramètres critiques à vérifier
    local params=(
        "net.ipv4.ip_forward"
        "net.ipv4.tcp_mtu_probing"
        "net.ipv4.ip_no_pmtu_disc"
        "net.core.rmem_max"
        "net.core.wmem_max"
    )
    
    local errors=0
    for param in "${params[@]}"; do
        local value=$(sysctl -n "$param" 2>/dev/null)
        if [[ -z "$value" ]]; then
            log_message "ERROR" "Paramètre $param non trouvé"
            ((errors++))
        fi
        echo "$param = $value" >> "$verification_file"
    done
    
    # Vérification spécifique à l'interface
    if ! ip link show "$interface" >/dev/null 2>&1; then
        log_message "ERROR" "Interface $interface non trouvée"
        ((errors++))
    fi
    
    if [[ $errors -gt 0 ]]; then
        log_message "ERROR" "$errors erreurs trouvées dans la configuration système"
        return 1
    fi
    
    log_message "INFO" "Vérification des paramètres système réussie"
    return 0
}

# Fonctions de gestion des configurations WireGuard

# Lecture de la configuration WireGuard
read_wireguard_config() {
    local config_file=$1
    
    if [[ ! -f "$config_file" ]]; then
        log_message "ERROR" "Fichier de configuration non trouvé: $config_file"
        return 1
    fi
    
    if ! check_wireguard_permissions "$config_file"; then
        log_message "ERROR" "Permissions incorrectes sur $config_file"
        return 1
    }
    
    # Lecture et validation de la configuration
    if ! grep -q '^\[Interface\]' "$config_file"; then
        log_message "ERROR" "Configuration invalide: section [Interface] manquante"
        return 1
    fi
    
    local current_mtu=$(grep -i '^MTU' "$config_file" | cut -d'=' -f2 | tr -d ' ')
    if [[ -n "$current_mtu" ]]; then
        log_message "INFO" "MTU actuel: $current_mtu"
        echo "MTU = $current_mtu"
    fi
    
    return 0
}

# Sauvegarde de la configuration
backup_wireguard_config() {
    local config_file=$1
    local backup_dir=$2
    local timestamp=$(date +%Y%m%d_%H%M%S)
    
    # Création du répertoire de sauvegarde
    mkdir -p "$backup_dir"
    
    # Sauvegarde avec métadonnées
    local backup_path="${backup_dir}/${timestamp}"
    mkdir -p "$backup_path"
    
    # Copie de la configuration
    cp "$config_file" "${backup_path}/$(basename "$config_file")"
    
    # Sauvegarde des paramètres système
    if [[ -f "/etc/sysctl.d/99-wireguard.conf" ]]; then
        cp "/etc/sysctl.d/99-wireguard.conf" "${backup_path}/sysctl-wireguard.conf"
    fi
    
    # Création des métadonnées
    cat << EOF > "${backup_path}/metadata.json"
{
    "timestamp": "$(date -Iseconds)",
    "interface": "$(basename "$config_file" .conf)",
    "mtu": "$(grep -i '^MTU' "$config_file" | cut -d'=' -f2 | tr -d ' ')",
    "system_info": "$(uname -a)",
    "backup_type": "pre_optimization"
}
EOF
    
    log_message "INFO" "Configuration sauvegardée dans ${backup_path}"
    return 0
}

# Validation de la configuration
validate_wireguard_config() {
    local config_file=$1
    
    # Vérification de la syntaxe
    if ! wg-quick strip "$config_file" >/dev/null 2>&1; then
        log_message "ERROR" "Syntaxe de configuration invalide"
        return 1
    fi
    
    # Vérification du MTU
    local mtu=$(grep -i '^MTU' "$config_file" | cut -d'=' -f2 | tr -d ' ')
    if [[ -n "$mtu" ]]; then
        if ! validate_mtu_range "$mtu" "$mtu"; then
            log_message "ERROR" "MTU invalide dans la configuration"
            return 1
        fi
    fi
    
    # Vérification des clés et adresses
    if ! grep -q '^PrivateKey' "$config_file" || \
       ! grep -q '^Address' "$config_file"; then
        log_message "ERROR" "Configuration incomplète"
        return 1
    fi
    
    return 0
}

# Mise à jour du MTU
update_wireguard_mtu() {
    local config_file=$1
    local new_mtu=$2
    local temp_file="${config_file}.tmp"
    
    # Validation du nouveau MTU
    if ! validate_mtu_range "$new_mtu" "$new_mtu"; then
        log_message "ERROR" "Nouvelle valeur MTU invalide: $new_mtu"
        return 1
    fi
    
    # Création d'une copie temporaire
    cp "$config_file" "$temp_file"
    
    # Mise à jour du MTU
    if grep -q '^MTU' "$config_file"; then
        sed -i "s/^MTU.*$/MTU = $new_mtu/" "$temp_file"
    else
        # Ajout du MTU s'il n'existe pas
        sed -i "/^\[Interface\]/a MTU = $new_mtu" "$temp_file"
    fi
    
    # Validation de la nouvelle configuration
    if ! validate_wireguard_config "$temp_file"; then
        log_message "ERROR" "La nouvelle configuration est invalide"
        rm -f "$temp_file"
        return 1
    fi
    
    # Application de la nouvelle configuration
    mv "$temp_file" "$config_file"
    chmod 600 "$config_file"
    
    log_message "INFO" "MTU mis à jour: $new_mtu"
    return 0
}

# Vérification des permissions
check_wireguard_permissions() {
    local config_file=$1
    local perms=$(stat -c %a "$config_file")
    
    if [[ "$perms" != "600" ]]; then
        log_message "ERROR" "Permissions trop permissives sur $config_file (actuel: $perms, requis: 600)"
        return 1
    fi
    
    if [[ $(stat -c %U "$config_file") != "root" ]]; then
        log_message "ERROR" "Le propriétaire doit être root"
        return 1
    fi
    
    return 0
}

# Vérification de la cohérence
check_wireguard_config_coherence() {
    local config_file=$1
    
    # Vérification des sections requises
    if ! grep -q '^\[Interface\]' "$config_file" || \
       ! grep -q '^\[Peer\]' "$config_file"; then
        log_message "ERROR" "Sections [Interface] et [Peer] requises"
        return 1
    fi
    
    # Vérification des paramètres obligatoires
    local required_params=("PrivateKey" "Address" "PublicKey" "AllowedIPs")
    for param in "${required_params[@]}"; do
        if ! grep -q "^${param}" "$config_file"; then
            log_message "ERROR" "Paramètre requis manquant: $param"
            return 1
        fi
    done
    
    # Vérification de la cohérence des adresses IP
    local interface_addr=$(grep '^Address' "$config_file" | cut -d'=' -f2 | tr -d ' ')
    local allowed_ips=$(grep '^AllowedIPs' "$config_file" | cut -d'=' -f2 | tr -d ' ')
    
    if ! validate_ip_network "$interface_addr" || \
       ! validate_ip_network "$allowed_ips"; then
        log_message "ERROR" "Adresses IP invalides"
        return 1
    fi
    
    return 0
}

# Validation des adresses IP et réseaux
validate_ip_network() {
    local ip_net=$1
    
    # Vérification basique du format
    if [[ ! "$ip_net" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$ ]]; then
        return 1
    fi
    
    return 0
}

# Restauration de la configuration
restore_wireguard_config() {
    local backup_file=$1
    local target_file=$2
    
    if [[ ! -f "$backup_file" ]]; then
        log_message "ERROR" "Fichier de sauvegarde non trouvé: $backup_file"
        return 1
    fi
    
    # Validation de la sauvegarde
    if ! validate_wireguard_config "$backup_file"; then
        log_message "ERROR" "La sauvegarde est invalide"
        return 1
    fi
    
    # Restauration
    cp "$backup_file" "$target_file"
    chmod 600 "$target_file"
    
    log_message "INFO" "Configuration restaurée depuis $backup_file"
    return 0
}

# Fonctions d'optimisation avancée

# Surveillance continue des performances
monitor_performance() {
    local interface=$1
    local stats_file="${TEMP_DIR}/performance_stats"
    local monitoring_interval=5
    local monitoring_duration=300  # 5 minutes
    
    log_message "INFO" "Démarrage de la surveillance des performances sur $interface"
    
    # Création du fichier de statistiques avec en-tête
    echo "timestamp,latency,throughput,packet_loss,jitter,tcp_window" > "$stats_file"
    
    local start_time=$(date +%s)
    local end_time=$((start_time + monitoring_duration))
    
    while [[ $(date +%s) -lt $end_time ]]; do
        # Mesures de performance
        local latency=$(ping -c 1 -W 1 "$SERVER_IP" | grep -oP 'time=\K[0-9.]+' || echo "NA")
        local throughput=$(iperf3 -c "$SERVER_IP" -t 1 -f m 2>/dev/null | awk '/receiver/ {print $7}' || echo "NA")
        local packet_loss=$(ping -c 10 -q "$SERVER_IP" 2>/dev/null | grep -oP '\d+(?=% packet loss)' || echo "NA")
        local jitter=$(ping -c 10 "$SERVER_IP" 2>/dev/null | awk -v RS="" '/rtt/ {print $7}' | cut -d/ -f2 || echo "NA")
        local tcp_window=$(ss -i | grep -i "$interface" | awk '/rto/ {print $4}' || echo "NA")
        
        # Enregistrement des mesures
        echo "$(date +%s),$latency,$throughput,$packet_loss,$jitter,$tcp_window" >> "$stats_file"
        
        sleep "$monitoring_interval"
    done
    
    analyze_performance_data "$stats_file"
}

# Analyse des données de performance
analyze_performance_data() {
    local stats_file=$1
    local analysis_file="${TEMP_DIR}/performance_analysis"
    
    log_message "INFO" "Analyse des données de performance..."
    
    # Calcul des statistiques
    awk -F',' 'NR>1 {
        # Somme pour moyennes
        lat_sum += $2; tput_sum += $3; loss_sum += $4; jit_sum += $5
        # Tracking min/max
        if(NR==2 || $2<min_lat) min_lat=$2
        if(NR==2 || $2>max_lat) max_lat=$2
        if(NR==2 || $3<min_tput) min_tput=$3
        if(NR==2 || $3>max_tput) max_tput=$3
    } END {
        count=NR-1
        printf "Performance Analysis Summary\n"
        printf "==========================\n"
        printf "Latency (ms)    : avg=%.2f min=%.2f max=%.2f\n", lat_sum/count, min_lat, max_lat
        printf "Throughput (Mbps): avg=%.2f min=%.2f max=%.2f\n", tput_sum/count, min_tput, max_tput
        printf "Packet Loss (%%): avg=%.2f\n", loss_sum/count
        printf "Jitter (ms)     : avg=%.2f\n", jit_sum/count
    }' "$stats_file" > "$analysis_file"
    
    # Détection des anomalies
    detect_performance_anomalies "$stats_file" >> "$analysis_file"
}

# Détection des anomalies de performance
detect_performance_anomalies() {
    local stats_file=$1
    local threshold_latency=100  # ms
    local threshold_loss=5       # %
    local threshold_jitter=20    # ms
    
    echo -e "\nPerformance Anomalies"
    echo "===================="
    
    awk -F',' -v lat="$threshold_latency" -v loss="$threshold_loss" -v jit="$threshold_jitter" '
    NR>1 {
        if($2 > lat) printf "High latency detected: %.2fms at %s\n", $2, strftime("%Y-%m-%d %H:%M:%S", $1)
        if($4 > loss) printf "High packet loss detected: %.2f%% at %s\n", $4, strftime("%Y-%m-%d %H:%M:%S", $1)
        if($5 > jit) printf "High jitter detected: %.2fms at %s\n", $5, strftime("%Y-%m-%d %H:%M:%S", $1)
    }' "$stats_file"
}

# Optimisation auto-adaptative
auto_adapt_parameters() {
    local interface=$1
    local current_mtu=$(ip link show "$interface" | grep -oP 'mtu \K\d+')
    local performance_stats="${TEMP_DIR}/performance_stats"
    
    log_message "INFO" "Démarrage de l'optimisation auto-adaptative..."
    
    # Surveillance initiale
    monitor_performance "$interface"
    
    # Analyse des données pour ajustement
    local avg_latency=$(awk -F',' 'NR>1 {sum+=$2} END {print sum/(NR-1)}' "$performance_stats")
    local avg_loss=$(awk -F',' 'NR>1 {sum+=$4} END {print sum/(NR-1)}' "$performance_stats")
    local avg_jitter=$(awk -F',' 'NR>1 {sum+=$5} END {print sum/(NR-1)}' "$performance_stats")
    
    # Décision d'ajustement basée sur les métriques
    local mtu_adjustment=0
    
    if (( $(echo "$avg_latency > 100" | bc -l) )); then
        mtu_adjustment=-20
    elif (( $(echo "$avg_loss > 2" | bc -l) )); then
        mtu_adjustment=-10
    elif (( $(echo "$avg_jitter > 15" | bc -l) )); then
        mtu_adjustment=-5
    elif (( $(echo "$avg_latency < 50" | bc -l) && $(echo "$avg_loss < 0.1" | bc -l) )); then
        mtu_adjustment=10
    fi
    
    # Application de l'ajustement si nécessaire
    if [[ $mtu_adjustment -ne 0 ]]; then
        local new_mtu=$((current_mtu + mtu_adjustment))
        if validate_mtu_range "$new_mtu" "$new_mtu"; then
            log_message "INFO" "Ajustement auto-adaptatif du MTU: $current_mtu -> $new_mtu"
            update_wireguard_mtu "/etc/wireguard/${interface}.conf" "$new_mtu"
        fi
    fi
}

# Optimisation proactive
optimize_proactively() {
    local interface=$1
    local optimization_interval=3600  # 1 heure
    
    log_message "INFO" "Démarrage de l'optimisation proactive..."
    
    while true; do
        # Collecte des métriques actuelles
        local current_stats=$(collect_current_metrics "$interface")
        
        # Analyse des tendances
        analyze_performance_trends "$current_stats"
        
        # Ajustement si nécessaire
        auto_adapt_parameters "$interface"
        
        sleep "$optimization_interval"
    done
}

# Collecte des métriques actuelles
collect_current_metrics() {
    local interface=$1
    local metrics_file="${TEMP_DIR}/current_metrics"
    
    # Mesures réseau
    local latency=$(ping -c 5 -q "$SERVER_IP" 2>/dev/null | awk -F'/' 'END{print $5}')
    local packet_loss=$(ping -c 10 -q "$SERVER_IP" 2>/dev/null | grep -oP '\d+(?=% packet loss)')
    local current_mtu=$(ip link show "$interface" | grep -oP 'mtu \K\d+')
    
    # Mesures système
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}')
    local mem_usage=$(free | awk '/Mem/{printf("%.2f"), $3/$2*100}')
    
    # Enregistrement des métriques
    cat << EOF > "$metrics_file"
timestamp=$(date +%s)
latency=$latency
packet_loss=$packet_loss
mtu=$current_mtu
cpu_usage=$cpu_usage
mem_usage=$mem_usage
EOF
    
    echo "$metrics_file"
}

# Analyse des tendances de performance
analyze_performance_trends() {
    local metrics_file=$1
    local trends_file="${TEMP_DIR}/performance_trends"
    local history_file="${TEMP_DIR}/metrics_history"
    
    # Ajout des métriques actuelles à l'historique
    cat "$metrics_file" >> "$history_file"
    
    # Analyse des tendances sur les dernières 24 heures
    awk -F'=' '
    BEGIN {
        OFS=","
        print "metric,trend,variation"
    }
    {
        if($1 == "timestamp") timestamp=$2
        if($1 == "latency") latency[timestamp]=$2
        if($1 == "packet_loss") loss[timestamp]=$2
        if($1 == "mtu") mtu[timestamp]=$2
    }
    END {
        # Calcul des tendances
        for(t in latency) {
            if(prev_lat) {
                lat_trend=(latency[t]-prev_lat)/prev_lat*100
                print "latency", lat_trend, latency[t]
            }
            prev_lat=latency[t]
        }
        for(t in loss) {
            if(prev_loss) {
                loss_trend=(loss[t]-prev_loss)/prev_loss*100
                print "packet_loss", loss_trend, loss[t]
            }
            prev_loss=loss[t]
        }
    }' "$history_file" > "$trends_file"
    
    # Analyse et recommandations
    generate_optimization_recommendations "$trends_file"
}

# Génération des recommandations d'optimisation
generate_optimization_recommendations() {
    local trends_file=$1
    local recommendations_file="${TEMP_DIR}/optimization_recommendations"
    
    log_message "INFO" "Génération des recommandations d'optimisation..."
    
    awk -F',' '
    NR>1 {
        if($1 == "latency" && $2 > 10) {
            print "RECOMMENDATION: Consider reducing MTU due to increasing latency trend"
        }
        if($1 == "packet_loss" && $2 > 5) {
            print "RECOMMENDATION: Investigate network stability issues"
        }
        if($1 == "latency" && $2 < -10) {
            print "RECOMMENDATION: Current optimizations are effective"
        }
    }' "$trends_file" > "$recommendations_file"
    
    if [[ -s "$recommendations_file" ]]; then
        log_message "INFO" "Nouvelles recommandations d'optimisation disponibles"
        cat "$recommendations_file" | while read -r line; do
            log_message "INFO" "$line"
        done
    fi
}

# Call main with all arguments
main "$@" 