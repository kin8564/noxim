#!/bin/bash

# FDMA channel-count sweep for Noxim WiNoC configurations.
# Varies the number of radio channels by editing hub default rx/tx channel lists,
# runs multiple seeds per point, and stores per-run + averaged metrics.

set -euo pipefail

CONFIG_FILE="${CONFIG_FILE:-../config_examples/sop_unicast.yaml}"
VC="${VC:-8}"
CHANNEL_VALUES="${CHANNEL_VALUES:-1 4 8 12 16}"
# PIR_VALUES="${PIR_VALUES:-0.01 0.02 0.03 0.04 0.05 0.06 0.07 0.08 0.09 0.10}"
PIR_VALUES="${PIR_VALUES:-0.001 0.002 0.003 0.004 0.005 0.006 0.007 0.008 0.009 0.01}"
NUM_RUNS="${NUM_RUNS:-10}"
SEED_STRIDE="${SEED_STRIDE:-100}"
SIM_TIME="${SIM_TIME:-}"
TIMEOUT_SEC="${TIMEOUT_SEC:-180}"
RESULTS_DIR="${RESULTS_DIR:-./final_results}"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RAW_CSV="${RESULTS_DIR}/fdma_channel_sweep_raw_${TIMESTAMP}.csv"
AVG_CSV="${RESULTS_DIR}/fdma_channel_sweep_avg_${TIMESTAMP}.csv"

mkdir -p "${RESULTS_DIR}"

if [[ ! -f "${CONFIG_FILE}" ]]; then
    echo "ERROR: config file not found: ${CONFIG_FILE}" >&2
    exit 1
fi

# Build comma-separated channel list: 0,1,...,(N-1)
build_channel_list() {
    local n="$1"
    local i
    local out=""

    if (( n < 1 )); then
        echo "ERROR: channel count must be >= 1 (got ${n})" >&2
        return 1
    fi

    for ((i = 0; i < n; i++)); do
        if [[ -z "${out}" ]]; then
            out="${i}"
        else
            out+=" ,${i}"
        fi
    done

    # Remove spaces around commas for cleaner YAML list formatting.
    echo "${out}" | sed 's/ ,/,/g'
}

# Replace first rx/tx channel list occurrence (expected in Hubs.defaults).
make_temp_config() {
    local src="$1"
    local channel_list="$2"
    local tmp
    tmp=$(mktemp /tmp/noxim_fdma_channels_XXXXXX.yaml)

    awk -v ch_list="${channel_list}" '
        /rx_radio_channels:/ && !done_rx {
            sub(/\[[^]]*\]/, "[" ch_list "]");
            done_rx = 1;
        }
        /tx_radio_channels:/ && !done_tx {
            sub(/\[[^]]*\]/, "[" ch_list "]");
            done_tx = 1;
        }
        { print }
    ' "${src}" > "${tmp}"

    echo "${tmp}"
}

extract_metrics() {
    local output="$1"
    local avg_ip_throughput global_avg_delay energy

    avg_ip_throughput=$(echo "${output}" | grep "% Average IP throughput" | awk '{print $NF}' | sed 's/[^0-9.eE+-]//g')
    global_avg_delay=$(echo "${output}" | grep "% Global average delay" | awk '{print $NF}' | sed 's/[^0-9.eE+-]//g')
    energy=$(echo "${output}" | grep "% Total energy" | awk '{print $NF}' | sed 's/[^0-9.eE+-]//g')

    if [[ -z "${avg_ip_throughput}" || -z "${global_avg_delay}" || -z "${energy}" ]]; then
        return 1
    fi

    echo "${avg_ip_throughput}|${global_avg_delay}|${energy}"
}

echo "Channels,PIR,Run,Seed,Avg_IP_Throughput_flits_cycle_IP,Global_Avg_Delay_cycles,Total_Energy_J" > "${RAW_CSV}"
echo "Channels,PIR,Avg_IP_Throughput_flits_cycle_IP,Avg_Global_Avg_Delay_cycles,Avg_Total_Energy_J,Valid_Runs" > "${AVG_CSV}"

echo "================================================"
echo "FDMA Channel Count Sweep"
echo "================================================"
echo "Config file: ${CONFIG_FILE}"
echo "VC: ${VC}"
echo "Channels: ${CHANNEL_VALUES}"
echo "PIR values: ${PIR_VALUES}"
echo "Runs per point: ${NUM_RUNS}"
echo "Timeout per run: ${TIMEOUT_SEC}s"
if [[ -n "${SIM_TIME}" ]]; then
    echo "Forced simulation time: ${SIM_TIME} cycles"
fi

echo

for channels in ${CHANNEL_VALUES}; do
    channel_list=$(build_channel_list "${channels}")
    temp_config=$(make_temp_config "${CONFIG_FILE}" "${channel_list}")

    echo "--- Testing channels=${channels} (list: [${channel_list}]) ---"

    for pir in ${PIR_VALUES}; do
        echo "  PIR=${pir}"

        for run in $(seq 0 $((NUM_RUNS - 1))); do
            seed=$((run * SEED_STRIDE))
            echo -n "    Run $((run + 1))/${NUM_RUNS}, seed=${seed}... "

            cmd=(./noxim -config "${temp_config}" -vc "${VC}" -pir "${pir}" poisson -seed "${seed}")
            if [[ -n "${SIM_TIME}" ]]; then
                cmd+=( -sim "${SIM_TIME}" )
            fi

            set +e
            output=$(timeout "${TIMEOUT_SEC}" "${cmd[@]}" 2>&1)
            rc=$?
            set -e

            if [[ ${rc} -eq 124 ]]; then
                echo "TIMEOUT"
                continue
            fi
            if [[ ${rc} -ne 0 ]]; then
                echo "FAILED (exit ${rc})"
                continue
            fi

            if ! metrics=$(extract_metrics "${output}"); then
                echo "FAILED (could not parse metrics)"
                continue
            fi

            IFS='|' read -r avg_ip_thr avg_dly energy <<< "${metrics}"
            printf "OK ip_thr=%.6e avg_delay=%.2f energy=%.3e\n" "${avg_ip_thr}" "${avg_dly}" "${energy}"
            echo "${channels},${pir},$((run + 1)),${seed},${avg_ip_thr},${avg_dly},${energy}" >> "${RAW_CSV}"
        done

        awk -F',' -v c="${channels}" -v p="${pir}" '
            BEGIN { ip=0; gd=0; en=0; n=0 }
            NR > 1 && $1 == c && $2 == p {
                ip += $5;
                gd += $6;
                en += $7;
                n += 1;
            }
            END {
                if (n > 0) {
                    printf "%s,%s,%.10e,%.6f,%.10e,%d\n", c, p, ip/n, gd/n, en/n, n;
                }
            }
        ' "${RAW_CSV}" >> "${AVG_CSV}"
    done

    rm -f "${temp_config}"
done

echo
echo "================================================"
echo "Sweep completed"
echo "Raw results:     ${RAW_CSV}"
echo "Averaged results:${AVG_CSV}"
echo "================================================"
echo

echo "Top channel count per PIR (max Avg_IP_Throughput):"
awk -F',' '
    NR == 1 { next }
    {
        pir = $2;
        channels = $1;
        ip_thr = $3;
        avg_dly = $4;
        avg_en = $5;

        if (!(pir in best_ip_thr) || ip_thr > best_ip_thr[pir]) {
            best_ip_thr[pir] = ip_thr;
            best_channels[pir] = channels;
            best_avg_dly[pir] = avg_dly;
            best_avg_en[pir] = avg_en;
        }
    }
    END {
        printf "PIR,Best_Channels,Avg_IP_Throughput,Avg_Global_Delay,Avg_Total_Energy\n";
        for (pir in best_channels) {
            printf "%s,%s,%.10e,%.6f,%.10e\n", pir, best_channels[pir], best_ip_thr[pir], best_avg_dly[pir], best_avg_en[pir];
        }
    }
' "${AVG_CSV}"
