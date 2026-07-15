from __future__ import annotations

import argparse
import json
import math
import statistics
from pathlib import Path
from typing import Any


EXPECTED_REQUESTS = 20
MEAN_COST_MAX = 0.005
P95_COST_MAX = 0.01
PROJECTED_100_MAX = 0.50
MEDIAN_LATENCY_MAX_MS = 5_000
P95_LATENCY_MAX_MS = 10_000


def percentile(values: list[float], percentile_value: float) -> float:
    ordered = sorted(values)
    return ordered[max(0, math.ceil(percentile_value * len(ordered)) - 1)]


def check(path: Path) -> dict[str, Any]:
    rows = [json.loads(line) for line in path.read_text().splitlines() if line.strip()]
    if len(rows) != EXPECTED_REQUESTS:
        raise ValueError(f"calibration requires exactly {EXPECTED_REQUESTS} requests")
    if not all(row.get("succeeded") is True for row in rows):
        raise ValueError("every calibration request must return a valid event response")
    costs = [float(row["request_cost_usd"]) for row in rows]
    latencies = [float(row["latency_ms"]) for row in rows]
    if any(cost < 0 for cost in costs) or any(latency < 0 for latency in latencies):
        raise ValueError("cost and latency must be non-negative")
    mean_cost = statistics.fmean(costs)
    p95_cost = percentile(costs, 0.95)
    median_latency = statistics.median(latencies)
    p95_latency = percentile(latencies, 0.95)
    projected_100 = mean_cost * 100
    gates = {
        "mean_cost": mean_cost <= MEAN_COST_MAX,
        "p95_cost": p95_cost <= P95_COST_MAX,
        "projected_100_cost": projected_100 <= PROJECTED_100_MAX,
        "median_latency": median_latency <= MEDIAN_LATENCY_MAX_MS,
        "p95_latency": p95_latency <= P95_LATENCY_MAX_MS,
    }
    return {
        "request_count": len(rows),
        "mean_cost_usd": mean_cost,
        "p95_cost_usd": p95_cost,
        "projected_100_cost_usd": projected_100,
        "median_latency_ms": median_latency,
        "p95_latency_ms": p95_latency,
        "gates": gates,
        "passed": all(gates.values()),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("records", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    report = check(args.records)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    print(json.dumps(report, indent=2, sort_keys=True))
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
