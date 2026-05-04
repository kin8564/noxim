#!/bin/bash

# SOP Wired PIR Sweep Metrics Script
# Tests: sop_wired topology with random traffic distribution
# PIR sweep: 0.001 to 0.01 (by 0.001 step)
# Runs: 10 simulations per configuration with different seeds
# Metrics: Total received packets, Received/Ideal flits Ratio, Total energy

set -e

# Configuration
TOPOLOGY="sop_wired"
VC_VALUES=(8)
PIR_VALUES=(0.001 0.002 0.003 0.004 0.005 0.006 0.007 0.008 0.009 0.01)
NUM_RUNS=10
RESULTS_DIR="./final_results"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RESULTS_FILE="${RESULTS_DIR}/sop_wired_packets_${TIMESTAMP}.csv"
AVG_RESULTS_FILE="${RESULTS_DIR}/sop_wired_packets_avg_${TIMESTAMP}.csv"

# Create results directory
mkdir -p "${RESULTS_DIR}"

# Initialize results file with header
echo "VC,PIR,Run,Total_Received_Packets,Received_Ideal_Flits_Ratio,Energy_J" > "${RESULTS_FILE}"
echo "VC,PIR,Avg_Total_Received_Packets,Avg_Received_Ideal_Flits_Ratio,Avg_Energy_J,Valid_Runs" > "${AVG_RESULTS_FILE}"

# Function to extract metrics from noxim output
extract_metrics() {
    local output=$1
    local received_packets=$(echo "$output" | grep "% Total received packets" | awk '{print $NF}' | sed 's/[^0-9.e-]*//g')
    local flit_ratio=$(echo "$output" | grep "% Received/Ideal flits Ratio" | awk '{print $NF}' | sed 's/[^0-9.e-]*//g')
    local energy=$(echo "$output" | grep "% Total energy" | awk '{print $NF}' | sed 's/[^0-9.e-]*//g')
    echo "$received_packets|$flit_ratio|$energy"
}

# Function to calculate averages
calculate_averages() {
    local packets_sum=0
    local ratio_sum=0
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
        IFS='|' read -r received_packets flit_ratio energy <<< "$metric_line"
        packets_sum=$(echo "$packets_sum + $received_packets" | bc -l)
        ratio_sum=$(echo "$ratio_sum + $flit_ratio" | bc -l)
        energy_sum=$(echo "$energy_sum + $energy" | bc -l)
    done

    echo "$(echo "scale=8; $packets_sum / $count" | bc -l)|$(echo "scale=8; $ratio_sum / $count" | bc -l)|$(echo "scale=10; $energy_sum / $count" | bc -l)"
}

# Main test loop
config_file="../config_examples/${TOPOLOGY}.yaml"

if [ ! -f "$config_file" ]; then
    echo "ERROR: Config file not found: $config_file"
    exit 1
fi

echo ""
echo "================================================"
echo "SOP Wired Topology PIR Sweep Metrics Test"
echo "================================================"
echo "Configuration: $config_file"
echo "Traffic Distribution: TRAFFIC_RANDOM (Poisson)"
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

            output=$(timeout 120 ./noxim -config "$config_file" -vc "$vc" -traffic random -pir "$pir" poisson -seed "$seed" 2>&1)

            if [ $? -eq 124 ]; then
                echo "TIMEOUT (120s exceeded)"
                continue
            fi

            metrics=$(extract_metrics "$output")

            if [ -z "$metrics" ]; then
                echo "FAILED to extract metrics"
                continue
            fi

            metrics_array[$run]="$metrics"

            IFS='|' read -r received_packets flit_ratio energy <<< "$metrics"
            printf "Total_Received_Packets=%.0f, Received_Ideal_Flits_Ratio=%.8f, Energy=%.10e J\n" "$received_packets" "$flit_ratio" "$energy"

            echo "$vc,$pir,$((run+1)),$received_packets,$flit_ratio,$energy" >> "${RESULTS_FILE}"
        done

        valid_runs=0
        for m in "${metrics_array[@]}"; do
            if [ -n "$m" ]; then
                valid_runs=$((valid_runs+1))
            fi
        done

        avg_metrics=$(calculate_averages "$valid_runs" "${metrics_array[@]}")
        IFS='|' read -r avg_packets avg_ratio avg_energy <<< "$avg_metrics"

        echo "$vc,$pir,$avg_packets,$avg_ratio,$avg_energy,$valid_runs" >> "${AVG_RESULTS_FILE}"

        echo ""
        echo "  AVERAGES for VC=$vc, PIR=$pir:"
        printf "    Avg Total Received Packets: %.0f\n" "$avg_packets"
        printf "    Avg Received/Ideal Flits Ratio: %.8f\n" "$avg_ratio"
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
        packets_sum[key] += $4
        ratio_sum[key] += $5
        energy_sum[key] += $6
        count[key] += 1
    }
    END {
        print "VC\tPIR\tAvg_Received_Packets\tAvg_Flit_Ratio\tAvg_Energy"
        print "---\t---\t---\t\t\t---\t\t---"
        for (key in packets_sum) {
            split(key, arr, ",")
            vc = arr[1]
            pir = arr[2]
            avg_p = packets_sum[key] / count[key]
            avg_r = ratio_sum[key] / count[key]
            avg_e = energy_sum[key] / count[key]
            printf "%d\t%.3f\t%.0f\t%.8f\t%.10e\n", vc, pir, avg_p, avg_r, avg_e
        }
    }' "${RESULTS_FILE}"

echo ""
echo "Test completed successfully!"