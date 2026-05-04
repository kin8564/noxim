#!/bin/bash

# SOP Wired PIR Sweep Test Script
# Tests: sop_wired topology with long distance traffic distribution
# PIR sweep: 0.001 to 0.01
# Runs: 10 simulations per configuration with different seeds
# Metrics: Throughput, Delay, Energy

set -e

# Configuration
TOPOLOGY="sop_wired"
VC_VALUES=(8)
PIR_VALUES=(0.001 0.002 0.003 0.004 0.005 0.006 0.007 0.008 0.009 0.01)
NUM_RUNS=10
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
NOXIM_BIN="${SCRIPT_DIR}/noxim"
RESULTS_DIR="${SCRIPT_DIR}/final_results"
RESULTS_FILE="${RESULTS_DIR}/wired_distance_pir_sweep_${TIMESTAMP}.csv"
AVG_RESULTS_FILE="${RESULTS_DIR}/wired_distance_pir_sweep_avg_${TIMESTAMP}.csv"

# Create results directory
mkdir -p "${RESULTS_DIR}"

# Initialize results files with header
echo "VC,PIR,Run,Throughput_flits_cycle_IP,Delay_cycles,Energy_J" > "${RESULTS_FILE}"
echo "VC,PIR,Avg_Throughput_flits_cycle_IP,Avg_Delay_cycles,Avg_Energy_J,Valid_Runs" > "${AVG_RESULTS_FILE}"

# Function to extract metrics from noxim output
extract_metrics() {
    local output=$1
    local throughput=$(echo "$output" | grep "% Average IP throughput" | awk '{print $NF}' | sed 's/[^0-9.e-]*//g' || true)
    local delay=$(echo "$output" | grep "% Global average delay" | awk '{print $NF}' | sed 's/[^0-9.e-]*//g' || true)
    local energy=$(echo "$output" | grep "% Total energy" | awk '{print $NF}' | sed 's/[^0-9.e-]*//g' || true)
    echo "$throughput|$delay|$energy"
}

# Function to calculate average of three metrics
calculate_averages() {
    local throughput_sum=0
    local delay_sum=0
    local energy_sum=0
    local count=$1
    shift

    if [ "$count" -eq 0 ]; then
        echo "0|0|0"
        return
    fi

    for metric_line in "$@"; do
        if [ -z "$metric_line" ]; then
            continue
        fi
        IFS='|' read throughput delay energy <<< "$metric_line"
        throughput_sum=$(echo "$throughput_sum + $throughput" | bc -l)
        delay_sum=$(echo "$delay_sum + $delay" | bc -l)
        energy_sum=$(echo "$energy_sum + $energy" | bc -l)
    done

    echo "$(echo "scale=8; $throughput_sum / $count" | bc -l)|$(echo "scale=6; $delay_sum / $count" | bc -l)|$(echo "scale=10; $energy_sum / $count" | bc -l)"
}

# Main test loop
config_file="${REPO_ROOT}/config_examples/${TOPOLOGY}.yaml"

if [ ! -x "$NOXIM_BIN" ]; then
    echo "ERROR: noxim binary not found or not executable: $NOXIM_BIN"
    exit 1
fi

if [ ! -f "$config_file" ]; then
    echo "ERROR: Config file not found: $config_file"
    exit 1
fi

echo ""
echo "================================================"
echo "SOP Wired Topology PIR Sweep Test"
echo "================================================"
echo "Configuration: $config_file"
echo "Traffic Distribution: TRAFFIC_LONG_DISTANCE (Poisson)"
echo "VC Values: ${VC_VALUES[@]}"
echo "PIR Values: ${PIR_VALUES[@]}"
echo "Number of simulations per configuration: $NUM_RUNS"
echo ""

for vc in "${VC_VALUES[@]}"; do
    echo ""
    echo "================================================"
    echo "Testing VC=$vc"
    echo "================================================"

    for pir in "${PIR_VALUES[@]}"; do
        echo ""
        echo "  PIR=$pir (Running $NUM_RUNS simulations)"

        metrics_array=()

        for run in $(seq 0 $((NUM_RUNS-1))); do
            seed=$((run * 100))

            echo -n "    Run $((run+1))/$NUM_RUNS (seed=$seed)... "

            set +e
            output=$(timeout 120 "$NOXIM_BIN" -config "$config_file" -vc "$vc" -traffic longdist -pir "$pir" poisson -seed "$seed" 2>&1)
            exit_code=$?
            set -e

            if [ "$exit_code" -eq 124 ]; then
                echo "TIMEOUT (120s exceeded)"
                continue
            elif [ "$exit_code" -ne 0 ]; then
                echo "FAILED (exit code $exit_code)"
                continue
            fi

            metrics=$(extract_metrics "$output")

            if [ -z "$metrics" ]; then
                echo "FAILED to extract metrics"
                continue
            fi

            metrics_array[$run]="$metrics"

            IFS='|' read throughput delay energy <<< "$metrics"
            printf "Throughput=%.6e flits/cycle/IP, Delay=%.2f cycles, Energy=%.2e J\n" "$throughput" "$delay" "$energy"

            echo "$vc,$pir,$((run+1)),$throughput,$delay,$energy" >> "${RESULTS_FILE}"
        done

        valid_runs=0
        for m in "${metrics_array[@]}"; do
            if [ -n "$m" ]; then
                valid_runs=$((valid_runs+1))
            fi
        done

        avg_metrics=$(calculate_averages "$valid_runs" "${metrics_array[@]}")
        IFS='|' read avg_throughput avg_delay avg_energy <<< "$avg_metrics"

        echo "$vc,$pir,$avg_throughput,$avg_delay,$avg_energy,$valid_runs" >> "${AVG_RESULTS_FILE}"

        echo ""
        echo "  AVERAGES for VC=$vc, PIR=$pir:"
        printf "    Avg Throughput: %.8e flits/cycle/IP\n" "$avg_throughput"
        printf "    Avg Delay: %.6f cycles\n" "$avg_delay"
        printf "    Avg Energy: %.10e J\n" "$avg_energy"
    done
done

echo ""
echo "================================================"
echo "Test Summary"
echo "================================================"
echo "All results saved to: $RESULTS_FILE"
echo "Averaged results saved to: $AVG_RESULTS_FILE"
echo ""
echo "Summary by VC and PIR:"
echo "---"

awk -F',' '
    NR == 1 { next }
    {
        vc = $1
        pir = $2
        key = vc "," pir
        throughput_sum[key] += $4
        delay_sum[key] += $5
        energy_sum[key] += $6
        count[key] += 1
    }
    END {
        print "VC\tPIR\tAvg_Throughput\t\tAvg_Delay\tAvg_Energy"
        print "---\t---\t---\t\t\t---\t\t---"
        for (key in throughput_sum) {
            split(key, arr, ",")
            vc = arr[1]
            pir = arr[2]
            avg_t = throughput_sum[key] / count[key]
            avg_d = delay_sum[key] / count[key]
            avg_e = energy_sum[key] / count[key]
            printf "%d\t%.3f\t%.8e\t%.6f\t%.10e\n", vc, pir, avg_t, avg_d, avg_e
        }
    }' "${RESULTS_FILE}"

echo ""
echo "Test completed successfully!"