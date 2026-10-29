# Measured simulation results

Clock assumption: 100 MHz; no STA/Fmax claim.

| Config | Scenario | Cycles | GB/s | Gb/s | Avg / max accepted latency | Peak W / R beats per cycle |
|---|---|---:|---:|---:|---:|---:|
| 4x4x256 | single-read | 609 | 2.6903 | 21.5225 | 71.4 / 75 | 0 / 1 |
| 4x4x256 | single-write | 641 | 2.5560 | 20.4480 | 75.2 / 79 | 1 / 0 |
| 4x4x256 | single-mixed | 641 | 5.1120 | 40.8961 | 73.3 / 79 | 1 / 1 |
| 4x4x256 | independent | 641 | 20.4480 | 163.5844 | 73.3 / 79 | 4 / 4 |
| 4x4x256 | hotspot | 2561 | 5.1180 | 40.9440 | 292.7 / 319 | 1 / 1 |
| 4x4x256 | backpressure | 1226 | 10.6910 | 85.5282 | 111.1 / 185 | 4 / 4 |
| 4x4x256 | sparse | 648 | 20.2272 | 161.8173 | 72.5 / 84 | 4 / 4 |
| 4x4x256 | burst-1 | 161 | 5.0882 | 40.7056 | 16.1 / 19 | 4 / 4 |
| 4x4x256 | burst-64 | 2177 | 24.0831 | 192.6644 | 256.3 / 271 | 4 / 4 |
| 4x4x256 | burst-max | 4225 | 24.8184 | 198.5469 | 500.3 / 527 | 4 / 4 |
