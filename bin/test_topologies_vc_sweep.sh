#!/bin/bash

# Topology VC Sweep Test Script
# Tests: cliche, torus, folded_torus, octagon, bft, spin
# VC sweep: 1, 2, 4, 8, 16
# Runs: 10 simulations per configuration with different seeds

set -e

# Configuration
TOPOLOGIES=("cliche" "torus" "folded_torus" "octagon" "bft" "spin")
VC_VALUES=(1 2 4 8 16)
NUM_RUNS=10
RESULTS_DIR="./vc_sweep_results"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RESULTS_FILE="${RESULTS_DIR}/topology_vc_sweep_${TIMESTAMP}.csv"

# Create results directory
mkdir -p "${RESULTS_DIR}"

# Initialize results file with header
echo "Topology,VC,Run,Avg_Delay_cycles,IP_Throughput_flits_cycle_IP,Energy_J" > "${RESULTS_FILE}"

# Function to extract metrics from noxim output
extract_metrics() {
    local output=$1
    local avg_delay=$(echo "$output" | grep "Global average delay" | awk '{print $NF}' | sed 's/[^0-9.e-]*//g')
    local throughput=$(echo "$output" | grep "Average IP throughput" | awk '{print $NF}' | sed 's/[^0-9.e-]*//g')
    local energy=$(echo "$output" | grep "Total energy" | awk '{print $NF}' | sed 's/[^0-9.e-]*//g')
    echo "$avg_delay|$throughput|$energy"
}

# Function to calculate average of three metrics
calculate_averages() {
    local delay_sum=0
    local throughput_sum=0
    local energy_sum=0
    local count=$1
    shift
    
    for metric_line in "$@"; do
        IFS='|' read delay throughput energy <<< "$metric_line"
        delay_sum=$(echo "$delay_sum + $delay" | bc -l)
        throughput_sum=$(echo "$throughput_sum + $throughput" | bc -l)
        energy_sum=$(echo "$energy_sum + $energy" | bc -l)
    done
    
    echo "$(echo "scale=6; $delay_sum / $count" | bc -l)|$(echo "scale=8; $throughput_sum / $count" | bc -l)|$(echo "scale=10; $energy_sum / $count" | bc -l)"
}

# Main test loop
total_tests=$(( ${#TOPOLOGIES[@]} * ${#VC_VALUES[@]} * NUM_RUNS ))
current_test=0

for topology in "${TOPOLOGIES[@]}"; do
    config_file="../config_examples/p_${topology}.yaml"
    
    if [ ! -f "$config_file" ]; then
        echo "ERROR: Config file not found: $config_file"
        continue
    fi
    
    echo ""
    echo "================================================"
    echo "Testing topology: $topology"
    echo "================================================"
    
    for vc in "${VC_VALUES[@]}"; do
        echo ""
        echo "  VC=$vc (Running $NUM_RUNS simulations with different seeds)"
        
        declare -a metrics_array
        
        for run in $(seq 0 $((NUM_RUNS-1))); do
            current_test=$((current_test+1))
            seed=$((run * 100)) # Unique seeds: 0, 100, 200, ..., 900
            
            echo -n "    Run $((run+1))/$NUM_RUNS (seed=$seed)... "
            
            # Run simulation with timeout
            output=$(timeout 120 ./noxim -config "$config_file" -vc "$vc" -seed "$seed" 2>&1)
            
            if [ $? -eq 124 ]; then
                echo "TIMEOUT (120s exceeded)"
                continue
            fi
            
            # Extract metrics from the output
            metrics=$(extract_metrics "$output")
            
            if [ -z "$metrics" ]; then
                echo "FAILED to extract metrics"
                continue
            fi
            
            metrics_array[$run]="$metrics"
            
            # Parse and display individual run results
            IFS='|' read delay throughput energy <<< "$metrics"
            printf "Delay=%s cycles, Throughput=%s flits/cycle/IP, Energy=%s J\n" "$delay" "$throughput" "$energy"
            
            # Log individual run to results file
            echo "$topology,$vc,$((run+1)),$delay,$throughput,$energy" >> "${RESULTS_FILE}"
        done
        
        # Calculate and display averages
        avg_metrics=$(calculate_averages "$NUM_RUNS" "${metrics_array[@]}")
        IFS='|' read avg_delay avg_throughput avg_energy <<< "$avg_metrics"
        
        echo ""
        echo "  AVERAGES for VC=$vc:"
        printf "    Avg Delay: %.6f cycles\n" "$avg_delay"
        printf "    Avg Throughput: %.8f flits/cycle/IP\n" "$avg_throughput"
        printf "    Avg Energy: %.10f J\n" "$avg_energy"
        echo ""
    done
done

echo ""
echo "================================================"
echo "Test Summary"
echo "================================================"
echo "All results saved to: $RESULTS_FILE"
echo ""
echo "Summary by topology and VC:"
echo "---"

# Generate summary table
awk -F',' '
    NR == 1 { next }  # Skip header
    {
        key = $1 "," $2
        delay_sum[key] += $4
        throughput_sum[key] += $5
        energy_sum[key] += $6
        count[key] += 1
    }
    END {
        print "Topology\t\tVC\tAvg_Delay\tAvg_Throughput\t\tAvg_Energy"
        print "---\t\t\t---\t----------\t--\t---------\t\t----------"
        for (key in delay_sum) {
            split(key, arr, ",")
            topology = arr[1]
            vc = arr[2]
            avg_d = delay_sum[key] / count[key]
            avg_t = throughput_sum[key] / count[key]
            avg_e = energy_sum[key] / count[key]
            printf "%-16s\t%d\t%.6f\t%.8f\t%.10f\n", topology, vc, avg_d, avg_t, avg_e
        }
    }
' "$RESULTS_FILE"

echo ""
echo "Test completed at $(date)"
