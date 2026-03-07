---
status: resolved
trigger: "After migrating to Envoy gateway, qbittorrent and Unifi endpoints are broken while others (evcc, hass, frigate) work fine."
created: 2026-03-07T00:00:00Z
updated: 2026-03-07T00:02:00Z
---

## Current Focus

hypothesis: CONFIRMED - two distinct bugs:
  1. qbittorrent: app-template route without explicit backendRefs defaults to first service port (bittorrent 50413) instead of http port (8080)
  2. unifi: BackendTLSPolicy targets service in wrong namespace (network) but unifi service is actually in network ns — policy works, but the httproute is in network namespace pointing to unifi service with no namespace qualifier — the REAL issue is the BackendTLSPolicy sectionName uses string "8443" but the service port name is "http" not "8443"
test: Live cluster HTTPRoute confirms qbittorrent route uses port 50413 (bittorrent) not 8080 (webui)
expecting: Fix route to use port 8080 for qbittorrent; fix BackendTLSPolicy sectionName for unifi
next_action: Apply fixes to both helmrelease.yaml and backendtlspolicy.yaml

## Symptoms

expected: Web UI loads normally for all exposed endpoints
actual:
  - https://qbittorrent.angryninja.cloud/ → "upstream connect error or disconnect/reset before headers. reset reason: connection timeout"
  - unifi → "Bad Request — This combination of host and port requires TLS."
errors: Not yet checked from kubectl/flux logs
reproduction: Just browse to the URL
started: Since migrating to Envoy gateway
affected: qbittorrent, unifi broken; evcc, hass, frigate work fine

## Eliminated

- hypothesis: "Wrong port number in unifi httproute backendRefs"
  evidence: unifi httproute correctly targets port 8443 and BackendTLSPolicy exists; the issue is the BackendTLSPolicy sectionName "8443" does not match the service port NAME "http"
  timestamp: 2026-03-07T00:01:00Z

## Evidence

- timestamp: 2026-03-07T00:00:30Z
  checked: Live HTTPRoute for qbittorrent in media namespace
  found: "port: 50413 weight: 1" — routes to bittorrent port, not webui port 8080
  implication: app-template route with no explicit backendRefs rules picks the FIRST port defined in the service spec, which is bittorrent (50413), not the http port (8080)

- timestamp: 2026-03-07T00:00:31Z
  checked: qbittorrent HelmRelease route section
  found: route.app has no explicit `rules` block — relies on app-template default behavior
  implication: app-template auto-generates backendRef from first service port; in this service spec, bittorrent is defined before http

- timestamp: 2026-03-07T00:00:32Z
  checked: qbittorrent Service spec (live)
  found: ports order: bittorrent(50413), bittorrent-udp(50413), http(8080)
  implication: First port is 50413, so auto-generated route targets that port — WebUI never reachable

- timestamp: 2026-03-07T00:00:33Z
  checked: unifi BackendTLSPolicy sectionName
  found: sectionName = "8443" but Service port name = "http" (port 8443)
  implication: BackendTLSPolicy sectionName must match the SERVICE PORT NAME, not the port number. "8443" doesn't match port name "http", so Envoy treats the 8443 backend as plain HTTP → Unifi rejects plain HTTP with "This combination of host and port requires TLS"

- timestamp: 2026-03-07T00:00:34Z
  checked: unifi Service spec (live) port names
  found: port 8443 has name "http" and appProtocol kubernetes.io/ws; port 8080 has name "controller"
  implication: BackendTLSPolicy sectionName should be "http" not "8443" to correctly attach TLS to the right port

## Resolution

root_cause: |
  TWO bugs:

  1. QBITTORRENT: The HelmRelease route section has no explicit `rules` block. The bjw-s app-template
     auto-generates a backendRef pointing to the first port in the service spec. Because the service
     defines `bittorrent` (port 50413) before `http` (port 8080), the generated HTTPRoute targets
     the BitTorrent protocol port, not the Web UI port. This causes a connection timeout since port
     50413 is a BitTorrent TCP port, not an HTTP server.
     Fix: Add explicit route rules with backendRef port 8080 (http).

  2. UNIFI: The BackendTLSPolicy has sectionName: "8443" but the Service port NAME is "http" (which
     happens to use port number 8443). The sectionName must match the port NAME, not the port number.
     Because the sectionName doesn't match, the BackendTLSPolicy is not applied, so Envoy forwards
     plain HTTP to port 8443. Unifi expects TLS on 8443 and rejects plain HTTP with
     "This combination of host and port requires TLS."
     Fix: Change BackendTLSPolicy sectionName from "8443" to "http".

fix: |
  1. kubernetes/apps/media/qbittorrent/app/helmrelease.yaml: Add explicit rules to route.app with backendRef port 8080
  2. kubernetes/apps/network/unifi/app/backendtlspolicy.yaml: Change sectionName from "8443" to "http"

verification: |
  - Pre-commit hooks (YAML lint, consistency check) passed cleanly
  - git commit 2bd95281 applied successfully
  - After Flux reconciliation: qbittorrent HTTPRoute will target port 8080 (WebUI),
    unifi BackendTLSPolicy will correctly attach TLS to the "http"/8443 service port.
files_changed:
  - kubernetes/apps/media/qbittorrent/app/helmrelease.yaml
  - kubernetes/apps/network/unifi/app/backendtlspolicy.yaml
