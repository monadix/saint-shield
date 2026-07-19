# Benchmark Results Format

Every run emits one JSON object plus referenced raw files. CSV summaries are derived, never canonical.

```json
{
  "schema": "l4pf-bench/v1",
  "run_id": "uuid",
  "timestamp_utc": "...",
  "git_commit": "...",
  "dirty": false,
  "build": {"zig": "0.16.0", "mode": "ReleaseSafe", "features": []},
  "host": {
    "cpu": "...", "microcode": "...", "numa": "...",
    "kernel": "...", "governor": "...", "smt": false
  },
  "nic": {
    "pci_id": "...", "firmware": "...", "driver": "...",
    "link_gbps": 100, "queues": 1, "offloads": []
  },
  "backend": {"name": "dpdk", "version": "25.11.2", "mode": "pmd"},
  "application": {
    "pipeline": ["..."], "generation_digest": "...",
    "batch_max": 64, "resources": {}
  },
  "traffic": {
    "generator": "...", "frame_profile": "64B", "protocol": "ipv4-udp",
    "flows": 1000, "offered_pps": 1000000, "duration_s": 60
  },
  "result": {
    "rx_pps": 0, "tx_pps": 0, "loss_packets": 0,
    "latency_ns": {"p50": 0, "p99": 0, "p999": 0, "max": 0},
    "cpu": {}, "perf": {}, "memory_bytes": {}
  },
  "valid": true,
  "invalid_reason": null,
  "raw_files": []
}
```

The actual implementation adds a JSON Schema under `bench/schemas/` and rejects missing environment fields for release comparisons. Secrets, host credentials, and proprietary topology identifiers are redacted before publication; redaction must not remove technical reproducibility fields.

Reports present medians and dispersion, not only best runs. Charts link back to exact run IDs and raw data.

