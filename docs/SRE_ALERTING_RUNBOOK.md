# SRE Observability, SLOs & Alerting Runbook (Phase 5)

## 1. Service Level Objectives (SLOs) & Error Budgets

| Metric | Target (SLO) | Measurement Window | Action on Exhaustion |
|--------|--------------|-------------------|----------------------|
| **Sync Delivery Success Rate** | **>= 99.9%** | Rolling 30 Days | Feature release freeze, prioritize stability sprints |
| **Handshake Latency (p95)** | **< 250ms** | 5-Minute Window | Investigate DNS/Relay routing latency |
| **Relay Server Availability** | **>= 99.95%** | Monthly Calendar | Incident RCA required, failover testing |

---

## 2. Four Golden Signals Monitoring

- **Latency:** Monitored via OpenTelemetry traces (`latency_ms`) on `TelemetryExporter`.
- **Traffic:** Measured via active peer sessions, packet count, and payload throughput in KB/s.
- **Errors:** Logged with cryptographic handshake failure counters and retry counts.
- **Saturation:** Tracked via Pod CPU/Memory thresholds and open file descriptors.

---

## 3. Incident Response Runbooks

### Incident 1: `RelayHighHandshakeFailureRate` (Critical)
1. **Symptoms:** Clients cannot establish tunnels via Relay; logs show `StateError: Identity changed` or cryptographic validation failure.
2. **Triaging:**
   - Check pod logs: `kubectl -n techuboard-prod logs -l app=techuboard-relay --tail=100`
   - Verify if SSL certificates expired or were rotated improperly.
   - Run penetration/health verification: `python3 scripts/pen_test.py`.
3. **Mitigation:**
   - Rollback to previous deployment revision: `kubectl -n techuboard-prod rollout undo deployment/techuboard-relay`.
   - If certificate rotation failed, re-inject cert-manager secret.

### Incident 2: `RelayDeliverySLOBreach` (Warning)
1. **Symptoms:** Users reporting delayed or missed clipboard sync events.
2. **Triaging:**
   - Verify network packet loss or WAN congestion.
   - Check if clients have fallen back to local LAN sync via UDP/TCP multicast.
3. **Mitigation:**
   - Scale out pods manually if HPA is saturated: `kubectl -n techuboard-prod scale deployment/techuboard-relay --replicas=5`.

---

## 4. Emergency Contacts & Pager Escalation
- **Primary On-Call:** SRE Team Lead
- **Escalation (Level 2):** Principal Architect / Lead Backend Engineer
- **Sign-off:** Principal Architect & CEO Approved.
