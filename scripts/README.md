# Monitoring checks

Use the helper script below to run both VM Insights health queries against Log Analytics:

```bash
./scripts/azcli/vm_insights_health.sh
```

Optional arguments:

```bash
# Override monitor resource group
./scripts/azcli/vm_insights_health.sh hubRG-Monitor

# Override monitor resource group and workspace name
./scripts/azcli/vm_insights_health.sh hubRG-Monitor <workspaceName>
```

The script executes:

- `docs/vm-insights-health.kql` (detailed telemetry status)
- `docs/vm-insights-rag-health.kql` (red/yellow/green summary)

Expected output (example):

```text
== VM Insights Detailed Health ==
Computer      ... HeartbeatRows ... VMProcessRows ... VMConnectionRows
LinuxVMpu54   ... 360           ... 36            ... 0
hubVMpu54     ... 9             ... 48            ... 348

== VM Insights RAG Health ==
Computer      Health  MissingSignals
LinuxVMpu54   GREEN   0
hubVMpu54     GREEN   0
```

Quick interpretation:

- `GREEN`: Heartbeat is fresh and VM Insights signals are present.
- `YELLOW`: Heartbeat exists but is stale or one/more signals are missing.
- `RED`: No heartbeat in the lookback window.

# Firewall DNS path check

Run one command to validate DNS packet path from Linux VM:

```bash
./scripts/azcli/fw_dns_path_check.sh
```

What it verifies:

- Direct DNS to `8.8.8.8` from VM times out (blocked/denied path).
- DNS to firewall `10.50.4.4` resolves successfully.
- Recent `AZFWDnsQuery` logs exist in Log Analytics.

Optional overrides:

```bash
VM_RG=hubRG-VM VM_NAME=LinuxVMpu54 FW_IP=10.50.4.4 ./scripts/azcli/fw_dns_path_check.sh
```
