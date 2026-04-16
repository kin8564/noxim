#!/usr/bin/env python3

import argparse
import csv
import re
import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import List, Tuple


FLOAT_RE = r"([+-]?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)"
PATTERNS = {
    "avg_ip_throughput": re.compile(r"% Average IP throughput \(flits/cycle/IP\):\s*" + FLOAT_RE),
    "global_avg_delay": re.compile(r"% Global average delay \(cycles\):\s*" + FLOAT_RE),
    "total_energy": re.compile(r"% Total energy \(J\):\s*" + FLOAT_RE),
    "wireless_utilization": re.compile(r"% Average wireless utilization:\s*" + FLOAT_RE),
}


@dataclass
class RunResult:
    channels: int
    pir: float
    avg_ip_throughput: float | None
    global_avg_delay: float | None
    total_energy: float | None
    wireless_utilization: float | None
    status: str
    log_file: Path


def frange(start: float, stop: float, step: float) -> List[float]:
    values = []
    value = start
    eps = step / 1000.0
    while value <= stop + eps:
        values.append(round(value, 4))
        value += step
    return values


def parse_metrics(output: str) -> Tuple[float, float, float, float]:
    extracted = {}
    for key, pattern in PATTERNS.items():
        match = pattern.search(output)
        if not match:
            raise ValueError(f"Could not find metric '{key}' in simulator output")
        extracted[key] = float(match.group(1))

    return (
        extracted["avg_ip_throughput"],
        extracted["global_avg_delay"],
        extracted["total_energy"],
        extracted["wireless_utilization"],
    )


def write_csv(results: List[RunResult], output_csv: Path) -> None:
    output_csv.parent.mkdir(parents=True, exist_ok=True)
    with output_csv.open("w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow([
            "channels",
            "pir",
            "avg_ip_throughput_flits_per_cycle_per_ip",
            "global_avg_delay_cycles",
            "total_energy_j",
            "wireless_utilization",
            "status",
            "log_file",
        ])
        for row in results:
            writer.writerow([
                row.channels,
                f"{row.pir:.2f}",
                "" if row.avg_ip_throughput is None else f"{row.avg_ip_throughput:.8f}",
                "" if row.global_avg_delay is None else f"{row.global_avg_delay:.8f}",
                "" if row.total_energy is None else f"{row.total_energy:.8f}",
                "" if row.wireless_utilization is None else f"{row.wireless_utilization:.8f}",
                row.status,
                str(row.log_file),
            ])


def write_markdown(results: List[RunResult], output_md: Path) -> None:
    output_md.parent.mkdir(parents=True, exist_ok=True)
    with output_md.open("w") as f:
        f.write("| Channels | PIR | Avg IP Throughput (flits/cycle/IP) | Global Avg Delay (cycles) | Total Energy (J) | Wireless Utilization | Status |\n")
        f.write("|---:|---:|---:|---:|---:|---:|:---|\n")
        for row in results:
            f.write(
                "| "
                + " | ".join([
                    str(row.channels),
                    f"{row.pir:.2f}",
                    "-" if row.avg_ip_throughput is None else f"{row.avg_ip_throughput:.6f}",
                    "-" if row.global_avg_delay is None else f"{row.global_avg_delay:.6f}",
                    "-" if row.total_energy is None else f"{row.total_energy:.6f}",
                    "-" if row.wireless_utilization is None else f"{row.wireless_utilization:.6f}",
                    row.status,
                ])
                + " |\n"
            )


def main() -> None:
    repo_root = Path(__file__).resolve().parents[1]

    parser = argparse.ArgumentParser(
        description=(
            "Run long-distance traffic sweep for 8/12/16/20 wireless channels over PIR 0.01..0.10 and compile results table."
        )
    )
    parser.add_argument("--noxim", type=Path, default=repo_root / "bin" / "noxim")
    parser.add_argument("--config-dir", type=Path, default=repo_root / "config_examples")
    parser.add_argument("--power", type=Path, default=repo_root / "bin" / "power.yaml")
    parser.add_argument("--channels", type=int, nargs="+", default=[8, 12, 16, 20])
    parser.add_argument("--pir-start", type=float, default=0.01)
    parser.add_argument("--pir-stop", type=float, default=0.10)
    parser.add_argument("--pir-step", type=float, default=0.01)
    parser.add_argument("--seed", type=int, default=0)
    parser.add_argument("--output-csv", type=Path, default=repo_root / "other" / "results" / "longdist_channels_sweep.csv")
    parser.add_argument("--output-md", type=Path, default=repo_root / "other" / "results" / "longdist_channels_sweep.md")
    parser.add_argument("--logs-dir", type=Path, default=repo_root / "other" / "results" / "logs")
    parser.add_argument("--dry-run", action="store_true", help="Print commands without running simulations")
    args = parser.parse_args()

    if not args.noxim.exists():
        raise SystemExit(f"noxim binary not found at: {args.noxim}")
    if not args.power.exists():
        raise SystemExit(f"power config not found at: {args.power}")

    pir_values = frange(args.pir_start, args.pir_stop, args.pir_step)
    args.logs_dir.mkdir(parents=True, exist_ok=True)

    results: List[RunResult] = []

    for channels in args.channels:
        cfg = args.config_dir / f"256_16h_{channels}channels.yaml"
        if not cfg.exists():
            raise SystemExit(f"configuration file not found: {cfg}")

        for pir in pir_values:
            pir_tag = f"{pir:.2f}".replace(".", "p")
            log_file = args.logs_dir / f"ch{channels}_pir{pir_tag}.log"

            cmd = [
                str(args.noxim),
                "-config", str(cfg),
                "-power", str(args.power),
                "-seed", str(args.seed),
                "-winoc",
                "-traffic", "longdist",
                "-pir", f"{pir:.2f}", "poisson",
            ]

            if args.dry_run:
                print("DRY-RUN:", " ".join(cmd))
                results.append(
                    RunResult(
                        channels=channels,
                        pir=pir,
                        avg_ip_throughput=None,
                        global_avg_delay=None,
                        total_energy=None,
                        wireless_utilization=None,
                        status="DRY_RUN",
                        log_file=log_file,
                    )
                )
                continue

            proc = subprocess.run(cmd, capture_output=True, text=True)
            combined_output = (proc.stdout or "") + "\n" + (proc.stderr or "")
            log_file.write_text(combined_output)

            if proc.returncode != 0:
                results.append(
                    RunResult(
                        channels=channels,
                        pir=pir,
                        avg_ip_throughput=None,
                        global_avg_delay=None,
                        total_energy=None,
                        wireless_utilization=None,
                        status=f"FAILED({proc.returncode})",
                        log_file=log_file,
                    )
                )
                continue

            try:
                avg_ip_throughput, global_avg_delay, total_energy, wireless_utilization = parse_metrics(combined_output)
                status = "OK"
            except ValueError as exc:
                avg_ip_throughput = None
                global_avg_delay = None
                total_energy = None
                wireless_utilization = None
                status = f"PARSE_ERROR: {exc}"

            results.append(
                RunResult(
                    channels=channels,
                    pir=pir,
                    avg_ip_throughput=avg_ip_throughput,
                    global_avg_delay=global_avg_delay,
                    total_energy=total_energy,
                    wireless_utilization=wireless_utilization,
                    status=status,
                    log_file=log_file,
                )
            )

            print(f"[{status}] channels={channels}, pir={pir:.2f}")

    write_csv(results, args.output_csv)
    write_markdown(results, args.output_md)

    print(f"\nWrote CSV table: {args.output_csv}")
    print(f"Wrote Markdown table: {args.output_md}")


if __name__ == "__main__":
    main()
