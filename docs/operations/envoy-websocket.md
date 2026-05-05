# Envoy Gateway WebSocket Configuration

## Problem

Applications using WebSocket connections (e.g., Home Assistant) experience:

1. Slow page loads that get progressively worse over time
2. WebSocket connections failing intermittently
3. Static file requests timing out while WebSocket connections work

Restarting the application temporarily fixes the issue, but it returns.

## Root Cause

**Connection Multiplexing Issue**: When Envoy uses HTTP/2 to communicate with backends, multiple requests share a single connection. Long-lived WebSocket connections can block other requests on the same connection, causing static file requests to hang.

Envoy Gateway's `ClientTrafficPolicy` advertises ALPN protocols in order `[h2, http/1.1]` by default. Browsers negotiate HTTP/2 via ALPN, but WebSocket upgrade requires HTTP/1.1 with a `101 Switching Protocols` response.

### Diagnosis

```bash
# HTTP/2 (default ALPN) - fails, no upgrade possible
curl -v https://hass.bakerhaus.cloud/api/websocket
# Output: ALPN: server accepted h2
# Result: HTTP/2 400 Bad Request

# HTTP/1.1 (forced) - works correctly
curl -v --http1.1 https://hass.bakerhaus.cloud/api/websocket
# Output: ALPN: server accepted http/1.1
# Output: HTTP/1.1 101 Switching Protocols
# Result: WebSocket upgrade successful
```

## Solution

### 1. ALPN Order (Required)

The `ClientTrafficPolicy` in `kubernetes/apps/network/envoy-gateway/app/envoy.yaml` must prefer HTTP/1.1:

```yaml
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: ClientTrafficPolicy
metadata:
  name: envoy
spec:
  tls:
    alpnProtocols:
      - http/1.1  # First — enables WebSocket upgrade
      - h2        # Fallback for standard traffic
```

### 2. Service appProtocol (Required for WebSocket apps)

The Service for WebSocket-heavy apps should declare the `appProtocol` so Envoy knows to handle WebSocket at the connection level:

```yaml
ports:
  - appProtocol: gateway.envoyproxy.io/ws
    name: http
    port: 8123
```

This is set via the HelmRelease in `kubernetes/apps/home/home-assistant/app/helmrelease.yaml`.

### 3. Per-Service BackendTrafficPolicy (Recommended)

For applications with mixed HTTP/WebSocket traffic, create a dedicated `BackendTrafficPolicy`. See `kubernetes/apps/home/home-assistant/app/backendtrafficpolicy.yaml`:

```yaml
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: BackendTrafficPolicy
metadata:
  name: home-assistant
spec:
  targetRefs:
    - group: gateway.networking.k8s.io
      kind: HTTPRoute
      name: home-assistant-app
  httpUpgrade:
    - type: websocket
  circuitBreaker:
    maxConnections: 1024
    maxPendingRequests: 1024
    maxParallelRequests: 1024
  tcpKeepalive:
    idleTime: 60s
    interval: 30s
    probes: 5
```

Key settings:

- **`httpUpgrade: websocket`**: Explicitly enables WebSocket upgrade support
- **`circuitBreaker`**: Prevents connection pool exhaustion from long-lived WebSocket connections
- **`tcpKeepalive`**: Detects and closes dead connections

Timeout settings (`requestTimeout: 0s`, `connectionIdleTimeout: 3600s`) are inherited from the global `BackendTrafficPolicy` in `kubernetes/apps/network/envoy-gateway/app/envoy.yaml`.

### Important: Do NOT use `useClientProtocol: true`

When a Service declares `appProtocol: gateway.envoyproxy.io/ws`, adding `useClientProtocol: true` to the `BackendTrafficPolicy` creates a conflict. Envoy cannot reconcile "mirror the client protocol" with the `appProtocol` directive, resulting in:

```
upstream connect error or disconnect/reset before headers. reset reason: protocol error
```

The `appProtocol` on the Service and `httpUpgrade` on the BackendTrafficPolicy are sufficient — `useClientProtocol` is only needed when the Service does **not** declare an `appProtocol`.

## Affected Applications

Any application that uses WebSocket connections:

- **Home Assistant** (`home/home-assistant`) — Real-time UI updates
- **Grafana** (`observability/grafana`) — Live dashboard updates
- **Open WebUI** (`ai/openwebui`) — Chat streaming

## Verification

```bash
curl -v https://hass.bakerhaus.cloud/api/websocket 2>&1 | grep -E "(ALPN|HTTP)"
# Expected:
# ALPN: server accepted http/1.1
# HTTP/1.1 101 Switching Protocols
```

Or in browser: DevTools > Network > WS tab — verify `101 Switching Protocols`.

## File Locations

| File | Purpose |
|------|---------|
| `kubernetes/apps/network/envoy-gateway/app/envoy.yaml` | ALPN order, global BackendTrafficPolicy, ClientTrafficPolicy, Gateways |
| `kubernetes/apps/home/home-assistant/app/backendtrafficpolicy.yaml` | HA-specific WebSocket + circuit breaker policy |
| `kubernetes/apps/home/home-assistant/app/helmrelease.yaml` | Service `appProtocol: gateway.envoyproxy.io/ws` |
