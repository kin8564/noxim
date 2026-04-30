#!/bin/bash

# SOP Wired PIR Sweep Test Script
# Tests: sop_wired topology with random traffic distribution
# PIR sweep: 0.01 to 0.1 (by 0.01 step)
# Runs: 10 simulations per configuration with different seeds
# Metrics: Throughput, Delay, Energy, Wireless Utilization

set -e

# Configuration
TOPOLOGY="sop_wired"
VC_VALUES=(8)
# PIR_VALUES=(0.01 0.02 0.03 0.04 0.05 0.06 0.07 0.08 0.09 0.10)
# PIR_VALUES=(0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0)
PIR_VALUES=(0.001 0.01 0.1 1.0)
NUM_RUNS=10
RESULTS_DIR="./wireless_results"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RESULTS_FILE="${RESULTS_DIR}/wired_pir_sweep_${TIMESTAMP}.csv"

# Create results directory
mkdir -p "${RESULTS_DIR}"

# Initialize results file with header
echo "VC,PIR,Run,Throughput_flits_cycle_IP,Delay_cycles,Energy_J,Wireless_Utilization" > "${RESULTS_FILE}"

# Function to extract metrics from noxim output
extract_metrics() {
    local output=$1
    local throughput=$(echo "$output" | grep "% Average IP throughput" | awk '{print $NF}' | sed 's/[^0-9.e-]*//g')
    local delay=$(echo "$output" | grep "% Global average delay" | awk '{print $NF}' | sed 's/[^0-9.e-]*//g')
    local energy=$(echo "$output" | grep "% Total energy" | awk '{print $NF}' | sed 's/[^0-9.e-]*//g')
    local wireless_util=$(echo "$output" | grep "% Average wireless utilization" | awk '{print $NF}' | sed 's/[^0-9.e-]*//g')
    echo "$throughput|$delay|$energy|$wireless_util"
}

# Function to calculate average of four metrics
calculate_averages() {
    local throughput_sum=0
    local delay_sum=0
    local energy_sum=0
    local wireless_sum=0
    local count=$1
    shift
    
    for metric_line in "$@"; do
        IFS='|' read throughput delay energy wireless <<< "$metric_line"
        throughput_sum=$(echo "$throughput_sum + $throughput" | bc -l)
        delay_sum=$(echo "$delay_sum + $delay" | bc -l)
        energy_sum=$(echo "$energy_sum + $energy" | bc -l)
        wireless_sum=$(echo "$wireless_sum + $wireless" | bc -l)
    done
    
    echo "$(echo "scale=8; $throughput_sum / $count" | bc -l)|$(echo "scale=6; $delay_sum / $count" | bc -l)|$(echo "scale=10; $energy_sum / $count" | bc -l)|$(echo "scale=8; $wireless_sum / $count" | bc -l)"
}

# Main test loop
config_file="../config_examples/${TOPOLOGY}.yaml"

if [ ! -f "$config_file" ]; then
    echo "ERROR: Config file not found: $config_file"
    exit 1
fi

echo ""
echo "================================================"
echo "SOP Wired Topology PIR Sweep Test"
echo "================================================"
echo "Configuration: $config_file"
echo "Traffic Distribution: TRAFFIC_RANDOM"
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
        
        declare -a metrics_array
        
        for run in $(seq 0 $((NUM_RUNS-1))); do
            seed=$((run * 100)) # Unique seeds: 0, 100, 200, ..., 900
            
            echo -n "    Run $((run+1))/$NUM_RUNS (seed=$seed)... "
            
            # Run simulation with timeout
            output=$(timeout 120 ./noxim -config "$config_file" -vc "$vc" -pir "$pir" poisson -seed "$seed" 2>&1)
            
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
            IFS='|' read throughput delay energy wireless <<< "$metrics"
            printf "Throughput=%.6e flits/cycle/IP, Delay=%.2f cycles, Energy=%.2e J, Wireless_Util=%.4f\n" "$throughput" "$delay" "$energy" "$wireless"
            
            # Log individual run to results file
            echo "$vc,$pir,$((run+1)),$throughput,$delay,$energy,$wireless" >> "${RESULTS_FILE}"
        done
        
        # Calculate and display averages
        avg_metrics=$(calculate_averages "$NUM_RUNS" "${metrics_array[@]}")
        IFS='|' read avg_throughput avg_delay avg_energy avg_wireless <<< "$avg_metrics"
        
        echo ""
        echo "  AVERAGES for VC=$vc, PIR=$pir:"
        printf "    Avg Throughput: %.8e flits/cycle/IP\n" "$avg_throughput"
        printf "    Avg Delay: %.6f cycles\n" "$avg_delay"
        printf "    Avg Energy: %.10e J\n" "$avg_energy"
        printf "    Avg Wireless Utilization: %.8f\n" "$avg_wireless"
    done
done

echo ""
echo "================================================"
echo "Test Summary"
echo "================================================"
echo "All results saved to: $RESULTS_FILE"
echo ""
echo "Summary by VC and PIR:"
echo "---"

# Generate summary table
awk -F',' '
    NR == 1 { next }  # Skip header
    {
        vc = $1
        pir = $2
        key = vc "," pir
        throughput_sum[key] += $4
        delay_sum[key] += $5
        energy_sum[key] += $6
        wireless_sum[key] += $7
        count[key] += 1
    }
    END {
        print "VC\tPIR\tAvg_Throughput\t\tAvg_Delay\tAvg_Energy\t\tWireless_Util"
        print "---\t---\t---\t\t\t---\t\t---\t\t\t---"
        for (key in throughput_sum) {
            split(key, arr, ",")
            vc = arr[1]
            pir = arr[2]
            avg_t = throughput_sum[key] / count[key]
            avg_d = delay_sum[key] / count[key]
            avg_e = energy_sum[key] / count[key]
            avg_w = wireless_sum[key] / count[key]
            printf "%d\t%.2f\t%.8e\t%.6f\t%.10e\t%.8f\n", vc, pir, avg_t, avg_d, avg_e, avg_w
        }
    }' "${RESULTS_FILE}"

echo ""
echo "Test completed successfully!"
