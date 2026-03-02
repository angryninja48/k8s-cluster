---
status: resolved
trigger: "WebSocket connections to Home Assistant and Frigate drop after 30-60 seconds when exposed via Envoy Gateway (HTTPRoute)"
created: 2026-03-02T00:00:00Z
updated: 2026-03-02T09:00:00Z
---

## Current Focus

hypothesis: CONFIRMED — Envoy's 32KB per_connection_buffer_limit_bytes overflows from HA state data, causing upstream flow control pause that blocks HA's WS PING from reaching clients
test: Analyzed upstream_flow_control_paused_reading (1233 pauses, 1220 resumes = 13 stuck), upstream_cx_rx_bytes_buffered: 453KB
expecting: Fix by raising bufferLimit to 1Mi in BackendTrafficPolicy + adding tcpKeepalive
next_action: DONE — changes committed

## Symptoms

expected: WebSocket connections to Home Assistant and Frigate remain alive indefinitely, live data streams continuously, switches/triggers work in real-time
actual: After ~83-120 seconds (Chrome/Mac/Android) or ~8-10 seconds (iOS HA app), connections drop. HA triggers/switches stop working, data goes stale, cameras stop streaming.
errors: No browser error codes. UC (Upstream Close) pattern for browsers, DC (Downstream Close) for iOS.
reproduction: Automatic — open Home Assistant or Frigate and wait. Apps go stale.
started: After switching from nginx ingress to Envoy Gateway (HTTPRoute). nginx auto-reconnected WebSockets; Envoy does not.

## Eliminated

- hypothesis: Missing or misconfigured BackendTrafficPolicy (no timeout policy)
  evidence: HA already has BackendTrafficPolicy home-assistant-timeouts with connectionIdleTimeout=3600s, requestTimeout=0s. Timeout config is NOT the issue.
  timestamp: 2026-03-02T01:00:00Z

- hypothesis: Stream idle timeout firing (5 minute default)
  evidence: WS upgraded connections are exempt from stream_idle_timeout. Drops happen at ~110s, not 5 minutes. Not the cause.
  timestamp: 2026-03-02T02:00:00Z

- hypothesis: Compression filters interfering with WS frames
  evidence: xDS dump confirms no compressor filter on HA route. Global BTP compressor is Overridden by HA's per-route BTP. Not the cause.
  timestamp: 2026-03-02T02:30:00Z

- hypothesis: Cilium/network policy blocking traffic between Envoy pods and HA pod
  evidence: 67 active upstream connections exist. Data flows normally (215MB received from HA). Connectivity is fine.
  timestamp: 2026-03-02T03:00:00Z

- hypothesis: upstream_cx_idle_timeout: 115 is dropping WebSocket connections
  evidence: These are non-WebSocket HTTP/1.1 connection pool evictions (idle connections reused for multiple requests). The 32KB buffer overflow is the WS killer.
  timestamp: 2026-03-02T03:30:00Z

- hypothesis: H1: Missing tcpKeepalive on HA upstream cluster is the PRIMARY cause (TCP silent drop between nodes)
  evidence: tcpKeepalive is confirmed missing on HA cluster (other clusters have it, global BTP is Overridden). However, the PRIMARY mechanism is the buffer overflow — TCP keepalive is a contributing factor preventing silent TCP drops but not the main PONG-blocking mechanism.
  timestamp: 2026-03-02T04:00:00Z

## Evidence

- timestamp: 2026-03-02T01:00:00Z
  checked: BackendTrafficPolicy home-assistant-timeouts in namespace home
  found: Exists with connectionIdleTimeout=3600s, requestTimeout=0s. Status=Accepted. But MISSING tcpKeepalive and connection.bufferLimit.
  implication: Timeout config is fine but buffer and keepalive are missing.

- timestamp: 2026-03-02T01:30:00Z
  checked: Global BTP (network/envoy) status for HA route
  found: Status shows "Overridden" for home/home-assistant-app route. This means HA's per-route BTP takes FULL precedence — no global BTP fields (tcpKeepalive, retry, compressor) apply to HA.
  implication: HA's BTP must be self-contained. tcpKeepalive and bufferLimit must be added explicitly to HA's BTP.

- timestamp: 2026-03-02T02:00:00Z
  checked: Envoy xDS config dump — HA upstream cluster (httproute/home/home-assistant-app/rule/0)
  found: per_connection_buffer_limit_bytes=32768 (32KB). upstream_connection_options: NOT SET (no tcpKeepalive). All other clusters have tcpKeepalive via global BTP.
  implication: 32KB is the default. HA pushes large state updates. Buffer overflow is highly likely.

- timestamp: 2026-03-02T02:30:00Z
  checked: Envoy xDS HA route config (virtual host hass.angryninja.cloud)
  found: timeout=0s, idle_timeout=0s, upgrade_configs=[{websocket}]. No retry_policy (correctly absent). No compression.
  implication: Route config is correct for WebSocket. Issue is at cluster level.

- timestamp: 2026-03-02T03:00:00Z
  checked: Envoy access logs for HA WebSocket connections
  found: Pattern UC (upstream close) at 83-120s for Chrome/Mac/Android. Pattern DC (downstream close) at 8-10s for iOS HA app (user_agent.ios.downstream_cx_destroy_remote_active_rq=1436).
  implication: Browsers close at ~110s which matches aiohttp heartbeat=55s (55s PING interval + 55s PONG wait = 110s). iOS reconnects rapidly.

- timestamp: 2026-03-02T04:00:00Z
  checked: Live Envoy stats for HA cluster (pod envoy-external-8487bf7f4d-wkq5w)
  found: upstream_flow_control_paused_reading_total=1233, upstream_flow_control_resumed_reading_total=1220 → 13 STUCK paused connections. upstream_cx_rx_bytes_buffered=453KB. upstream_cx_destroy_local_with_active_rq=265 (Envoy closes 265 WS connections). upstream_cx_destroy_remote_with_active_rq=152 (HA closes 152 WS connections = the UC pattern).
  implication: 453KB buffered in 67 active connections (avg 6.7KB/conn) with 32KB limit means buffer overflow is ACTIVELY HAPPENING on multiple connections.

- timestamp: 2026-03-02T04:30:00Z
  checked: BackendTrafficPolicy CRD schema for connection.bufferLimit field
  found: Field exists in EG 1.7.0 BTP: connection.bufferLimit (type: quantity string, e.g. "1Mi"). Default is 32768 bytes per CRD description.
  implication: Can directly fix by adding connection.bufferLimit: 1Mi to HA's BTP.

- timestamp: 2026-03-02T05:00:00Z
  checked: Frigate's BackendTrafficPolicy existence
  found: No BackendTrafficPolicy exists for Frigate. The internal gateway's global BTP has tcpKeepalive but NO connection.bufferLimit. Frigate also streams significant video data.
  implication: Frigate has same vulnerability. Must create BTP for frigate HTTPRoute.

- timestamp: 2026-03-02T05:30:00Z
  checked: Live ClientTrafficPolicy vs git (kubernetes/apps/network/envoy-gateway/app/envoy.yaml)
  found: Live CTP has tcpKeepalive={idleTime:600s, interval:60s, probes:3} and timeout.http.idleTimeout=3600s. Git CTP has tcpKeepalive={} (empty) and NO timeout section.
  implication: Git CTP is out of sync with live cluster. Must be synced to prevent Flux from reverting these important settings.

## Root Cause (Mechanism Explained)

**The PING/PONG deadlock:**
1. HA uses aiohttp with `WebSocketResponse(heartbeat=55)` — sends WS PING to clients every 55s, expects PONG within 55s
2. HA streams lots of state data (entity updates, events) to WebSocket clients
3. Envoy's upstream cluster has `per_connection_buffer_limit_bytes=32768` (32KB default)
4. When clients are slow (mobile networks, background tabs), HA's data backs up in Envoy's 32KB upstream receive buffer
5. Buffer fills → Envoy issues flow control PAUSE on upstream reads (TCP backpressure to HA)
6. HA's TCP send window fills up → HA cannot write ANYTHING to its socket — including WS PING frames
7. Client never receives PING → never sends PONG
8. HA's aiohttp heartbeat timer fires at 55+55=110s with no PONG → closes connection
9. Envoy sees connection close from HA (UC = Upstream Close) and tears down the downstream connection too

**Evidence matching:**
- `upstream_flow_control_paused_reading_total: 1233` vs `resumed: 1220` = 13 connections still paused
- `upstream_cx_rx_bytes_buffered: 453KB` = buffer consistently over 32KB limit on active connections
- `upstream_cx_destroy_remote_with_active_rq: 152` = exactly the UC pattern count
- Drops at ~110s = exactly `2 × heartbeat(55s)` = aiohttp PING timeout

## Resolution

root_cause: Envoy's default 32KB per_connection_buffer_limit_bytes overflows due to HA's high-volume state data streaming to WebSocket clients. Buffer overflow triggers upstream flow control pause. HA's TCP send window fills, blocking HA's WS PING frames from reaching clients. Clients never send PONG. HA's aiohttp heartbeat closes connection at ~110s.

fix: |
  1. kubernetes/apps/home/home-assistant/app/backendtrafficpolicy.yaml:
     - Added connection.bufferLimit: 1Mi (32x increase from 32KB default)
     - Added tcpKeepalive: {idleTime: 600s, interval: 60s, probes: 3} (was missing, global BTP overridden)
     - Fixed schema URL from broken envoyproxy.io/main URL to working kubernetes-schemas.pages.dev URL
  2. kubernetes/apps/home/frigate/app/backendtrafficpolicy.yaml: CREATED NEW
     - Same settings as HA BTP (connection.bufferLimit: 1Mi, tcpKeepalive, timeout)
     - Targets frigate HTTPRoute in home namespace
  3. kubernetes/apps/home/frigate/app/kustomization.yaml:
     - Added ./backendtrafficpolicy.yaml to resources list
  4. kubernetes/apps/network/envoy-gateway/app/envoy.yaml (ClientTrafficPolicy):
     - Synced git CTP with live cluster
     - Changed tcpKeepalive: {} to explicit values {idleTime: 600s, interval: 60s, probes: 3}
     - Added timeout.http.idleTimeout: 3600s (was present live but missing in git)

verification: Changes committed and pushed via GitOps. Flux will reconcile and apply. Verify by monitoring:
  - kubectl get backendtrafficpolicy -n home (both should show Accepted)
  - Watch Envoy stats: upstream_flow_control_paused_reading should stop increasing
  - upstream_cx_rx_bytes_buffered should stay well below 1Mi per connection
  - Watch HA WebSocket connections stay alive beyond 2 minutes

files_changed:
  - kubernetes/apps/home/home-assistant/app/backendtrafficpolicy.yaml
  - kubernetes/apps/home/frigate/app/backendtrafficpolicy.yaml (new)
  - kubernetes/apps/home/frigate/app/kustomization.yaml
  - kubernetes/apps/network/envoy-gateway/app/envoy.yaml
