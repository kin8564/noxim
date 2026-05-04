#!/bin/bash

# SOP Unicast VC & PIR Sweep Test Script
# Tests: sop_unicast topology with long distance traffic distribution
# VC sweep: 1, 4, 8, 12, 16
# PIR sweep: 0.001 to 0.01 (by 0.001 step)
# Runs: 10 simulations per configuration with different seeds
# Metrics: Avg IP Throughput, Global Avg Delay, Total Energy

set -e

# Configuration
TOPOLOGY="sop_unicast"
# VC_VALUES=(1 4 8 12 16)
VC_VALUES=(1)
# PIR_VALUES=(0.01 0.02 0.03 0.04 0.05 0.06 0.07 0.08 0.09 0.10)
PIR_VALUES=(0.02 0.03 0.04 0.05 0.06 0.07 0.08 0.09 0.10)
# PIR_VALUES=(0.001 0.002 0.003 0.004 0.005 0.006 0.007 0.008 0.009 0.01)
NUM_RUNS=10
RESULTS_DIR="./final_results"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RESULTS_FILE="${RESULTS_DIR}/sop_unicast_distance_vc_pir_sweep_${TIMESTAMP}.csv"
AVG_RESULTS_FILE="${RESULTS_DIR}/sop_unicast_distance_vc_pir_sweep_avg_${TIMESTAMP}.csv"

# Create results directory
mkdir -p "${RESULTS_DIR}"

# Initialize results file with header
echo "VC,PIR,Run,Avg_IP_Throughput_flits_cycle_IP,Global_Avg_Delay_cycles,Total_Energy_J" > "${RESULTS_FILE}"
echo "VC,PIR,Avg_IP_Throughput_flits_cycle_IP,Avg_Global_Avg_Delay_cycles,Avg_Total_Energy_J,Valid_Runs" > "${AVG_RESULTS_FILE}"

# Function to extract metrics from noxim output
extract_metrics() {
    local output=$1
    local avg_ip_throughput=$(echo "$output" | grep "% Average IP throughput" | awk '{print $NF}' | sed 's/[^0-9.e-]*//g')
    local avg_delay=$(echo "$output" | grep "% Global average delay" | awk '{print $NF}' | sed 's/[^0-9.e-]*//g')
    local energy=$(echo "$output" | grep "% Total energy" | awk '{print $NF}' | sed 's/[^0-9.e-]*//g')
    echo "$avg_ip_throughput|$avg_delay|$energy"
}

# Function to calculate average of three metrics
calculate_averages() {
    local avg_ip_throughput_sum=0
    local avg_delay_sum=0
    local energy_sum=0
    local count=$1
    shift
    
    for metric_line in "$@"; do
        IFS='|' read -r avg_ip_throughput avg_delay energy <<< "$metric_line"
        avg_ip_throughput_sum=$(echo "$avg_ip_throughput_sum + $avg_ip_throughput" | bc -l)
        avg_delay_sum=$(echo "$avg_delay_sum + $avg_delay" | bc -l)
        energy_sum=$(echo "$energy_sum + $energy" | bc -l)
    done
    
    echo "$(echo "scale=8; $avg_ip_throughput_sum / $count" | bc -l)|$(echo "scale=6; $avg_delay_sum / $count" | bc -l)|$(echo "scale=10; $energy_sum / $count" | bc -l)"
}

# Main test loop
config_file="../config_examples/${TOPOLOGY}.yaml"

if [ ! -f "$config_file" ]; then
    echo "ERROR: Config file not found: $config_file"
    exit 1
fi

echo ""
echo "================================================"
echo "SOP Unicast Topology VC & PIR Sweep Test"
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
        
        declare -a metrics_array
        
        for run in $(seq 0 $((NUM_RUNS-1))); do
            seed=$((run * 100)) # Unique seeds: 0, 100, 200, ..., 900
            
            echo -n "    Run $((run+1))/$NUM_RUNS (seed=$seed)... "
            
            # Run simulation with timeout
            output=$(timeout 120 ./noxim -config "$config_file" -vc "$vc" -pir "$pir" poisson -traffic longdist -seed "$seed" 2>&1)
            
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
            IFS='|' read -r avg_ip_throughput avg_delay energy <<< "$metrics"
            printf "Throughput=%.6e flits/cycle/IP, Delay=%.2f cycles, Energy=%.2e J\n" "$avg_ip_throughput" "$avg_delay" "$energy"
            
            # Log individual run to results file
            echo "$vc,$pir,$((run+1)),$avg_ip_throughput,$avg_delay,$energy" >> "${RESULTS_FILE}"
        done
        
        # Calculate and display averages
        valid_runs=${#metrics_array[@]}
        if [ "$valid_runs" -eq 0 ]; then
            echo "  No valid runs for VC=$vc, PIR=$pir"
            continue
        fi

        avg_metrics=$(calculate_averages "$valid_runs" "${metrics_array[@]}")
        IFS='|' read -r avg_ip_throughput avg_global_delay avg_energy <<< "$avg_metrics"
        
        echo ""
        echo "  AVERAGES for VC=$vc, PIR=$pir:"
        printf "    Avg IP Throughput: %.8e flits/cycle/IP\n" "$avg_ip_throughput"
        printf "    Avg Global Delay: %.6f cycles\n" "$avg_global_delay"
        printf "    Avg Total Energy: %.10e J\n" "$avg_energy"
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

# Generate averaged CSV and summary table
awk -F',' '
    NR == 1 { next }  # Skip header
    {
        vc = $1
        pir = $2
        key = vc "," pir
        avg_ip_throughput_sum[key] += $4
        global_delay_sum[key] += $5
        energy_sum[key] += $6
        count[key] += 1
    }
    END {
        print "VC,PIR,Avg_IP_Throughput_flits_cycle_IP,Avg_Global_Avg_Delay_cycles,Avg_Total_Energy_J,Valid_Runs" > "'"${AVG_RESULTS_FILE}"'"
        print "VC\tPIR\tAvg_IP_Throughput\tAvg_Global_Delay\tAvg_Total_Energy"
        print "---\t---\t---\t\t---\t\t---"
        for (key in avg_ip_throughput_sum) {
            split(key, arr, ",")
            vc = arr[1]
            pir = arr[2]
            avg_ip_t = avg_ip_throughput_sum[key] / count[key]
            avg_gd = global_delay_sum[key] / count[key]
            avg_energy = energy_sum[key] / count[key]
            printf "%d,%.3f,%.10e,%.6f,%.10e,%d\n", vc, pir, avg_ip_t, avg_gd, avg_energy, count[key] >> "'"${AVG_RESULTS_FILE}"'"
            printf "%d\t%.3f\t%.8e\t%.6f\t%.10e\n", vc, pir, avg_ip_t, avg_gd, avg_energy
        }
    }' "${RESULTS_FILE}"

echo ""
echo "Test completed successfully!"
