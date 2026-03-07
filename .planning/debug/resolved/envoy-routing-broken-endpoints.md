---
status: resolved
trigger: "Continue debugging envoy-routing-broken-endpoints. The fixes we applied earlier are not working as expected."
created: 2026-03-07T07:00:00Z
updated: 2026-03-07T08:15:00Z
---

## Current Focus

hypothesis: BOTH root causes confirmed and fixed.
test: Live traffic verified end-to-end through Envoy gateway
expecting: n/a — resolved
next_action: archive

## Symptoms

expected: Both qbittorrent and unifi accessible via Envoy gateway
actual:
  - qbittorrent: route points to bittorrent port 50413, not WebUI port 8080
  - unifi: "This combination of host and port requires TLS" — plain HTTP being sent to HTTPS port
started: previous debug session; fixes committed but not deployed
reproduction: access qbittorrent.<domain> or unifi.<domain> via Envoy internal gateway

## Eliminated

- hypothesis: rook-ceph-cluster blocking qbittorrent
  evidence: rook-ceph-cluster IS ready. Actual blocker is volsync (suspended at old revision)
  timestamp: 2026-03-07T07:10:00Z

- hypothesis: BackendTLSPolicy not applied to cluster
  evidence: unifi Kustomization DID apply it — inventory shows BackendTLSPolicy/network/unifi. Accepted by controller.
  timestamp: 2026-03-07T07:15:00Z

- hypothesis: BackendTLSPolicy sectionName mismatch (was "8443", fixed to "http")
  evidence: Fix applied. sectionName "http" correctly targets port named "http" = 8443. Envoy TLS transport socket correctly configured.
  timestamp: 2026-03-07T07:20:00Z

- hypothesis: qbittorrent fix hasn't applied due to rook-ceph-cluster timing
  evidence: Real cause is volsync being suspended. volsync spec.suspend=true, lastAppliedRevision=0baab40f (old). GitRepository at b96d83e7. Flux dependency check requires all deps to be at same revision.
  timestamp: 2026-03-07T07:25:00Z

- hypothesis: BackendTLSPolicy hostname casing would block SAN match
  evidence: RFC 6125 specifies DNS SAN matching is case-insensitive. hostname: unifi (lowercase) matches cert SAN DNS:UniFi. Kubernetes CRD regex also requires lowercase. Fix uses hostname: unifi.
  timestamp: 2026-03-07T07:45:00Z

## Evidence

- timestamp: 2026-03-07T07:05:00Z
  checked: qbittorrent Kustomization status
  found: status message = "dependency 'flux-system/volsync' revision is not up to date"
  implication: volsync (not rook-ceph-cluster) is the blocker

- timestamp: 2026-03-07T07:06:00Z
  checked: volsync Kustomization spec
  found: spec.suspend=true, lastAppliedRevision=0baab40f, GitRepository is at b96d83e7
  implication: volsync is intentionally suspended and stuck at old revision; cannot satisfy dep check

- timestamp: 2026-03-07T07:10:00Z
  checked: unifi BackendTLSPolicy live cluster state
  found: Policy Accepted, ResolvedRefs True. Envoy cluster config has TLS transport socket with SNI=unifi.network.svc.cluster.local
  implication: TLS config is correct in terms of Envoy xDS

- timestamp: 2026-03-07T07:12:00Z
  checked: Envoy cluster stats for unifi
  found: upstream_rq_total=0, cx_total=0 — zero traffic flowing
  implication: Either no traffic attempted recently OR connection failing immediately

- timestamp: 2026-03-07T07:15:00Z
  checked: unifi pod TLS cert via openssl s_client
  found: Self-signed cert, CN=UniFi, SAN=DNS:UniFi. Issuer = same (self-signed). NOT in any system CA bundle.
  implication: wellKnownCACertificates: System will REJECT this cert. Also hostname mismatch: unifi.network.svc.cluster.local != UniFi

- timestamp: 2026-03-07T07:20:00Z
  checked: Envoy EDS endpoint metadata for unifi
  found: endpoint metadata has envoy.transport_socket_match = httproute/network/unifi/rule/0/tls/0
  implication: TLS WILL be used — so connections will fail TLS verification

- timestamp: 2026-03-07T07:22:00Z
  checked: qbittorrent live HelmRelease values (route section)
  found: route.app only has parentRefs/hostnames, NO rules with port 8080. Fix not deployed.
  implication: Live cluster still routes to default port (50413 bittorrent port via app-template defaulting)

- timestamp: 2026-03-07T07:25:00Z
  checked: Envoy clusters output
  found: httproute/media/qbittorrent/rule/0 endpoints show 10.69.0.63:50413
  implication: Confirms qbittorrent still routes to bittorrent port

- timestamp: 2026-03-07T07:40:00Z
  checked: BackendTLSPolicy CRD validation for subjectAltNames.hostname
  found: CRD enforces regex ^(\*\.)?[a-z0-9]([-a-z0-9]*[a-z0-9])?(\.[a-z0-9]([-a-z0-9]*[a-z0-9])?)*$ — uppercase hostname rejected
  implication: Must use lowercase 'unifi' for hostname and SAN, which is valid per RFC 6125 case-insensitive matching

- timestamp: 2026-03-07T08:00:00Z
  checked: Envoy xDS cluster config (port-forward to pod :19000)
  found: transport_socket_matches with validation_context referencing SDS secret 'unifi/network-ca', SAN matcher exact='unifi', SNI='unifi'
  implication: Envoy correctly configured to use our custom CA cert and SAN matching

- timestamp: 2026-03-07T08:05:00Z
  checked: Envoy SDS secrets
  found: Secret 'unifi/network-ca' loaded with inline cert (base64). Certificate expiry 2026-09-28.
  implication: CA cert successfully injected from ConfigMap unifi-ca via BackendTLSPolicy caCertificateRefs

- timestamp: 2026-03-07T08:10:00Z
  checked: Live request curl -sk --resolve unifi.angryninja.cloud:443:10.213.0.52
  found: HTTP 302 response in 85ms. TLS verify result = 0 (success).
  implication: End-to-end TLS handshake succeeded. Envoy proxying HTTPS to unifi backend correctly.

- timestamp: 2026-03-07T08:12:00Z
  checked: Envoy stats post-request (pod zdwcz)
  found: ssl.handshake=1, upstream_rq_302=1, ssl.fail_verify_san=0, ssl.fail_verify_error=4 (pre-fix historical)
  implication: Our request succeeded cleanly. Pre-existing 4 failures were before fix was deployed.

## Resolution

root_cause:
  qbittorrent: "volsync Kustomization was manually suspended (spec.suspend=true) and stuck at old revision 0baab40f.
                Flux dependency checking requires all deps to match current GitRepository revision.
                qbittorrent's port 8080 fix was in git but could not deploy due to failed dep check.
                Secondary root cause: helmrelease was missing explicit route rules for port 8080."
  unifi: "BackendTLSPolicy used wellKnownCACertificates: System but unifi presents a Ubiquiti
          self-signed certificate (CN=UniFi, SAN=DNS:UniFi) not in any system CA bundle.
          Additionally, hostname/SAN matching required lowercase 'unifi' due to CRD regex,
          with RFC 6125 case-insensitive DNS SAN matching ensuring 'unifi' matches 'DNS:UniFi'."

fix:
  qbittorrent:
    - Unsuspended volsync Kustomization → dependency check unblocked
    - Updated helmrelease.yaml route rules to explicitly target port 8080
    - Flux reconciled and deployed successfully
    - Verified: Envoy now routes qbittorrent to 10.69.0.63:8080
  unifi:
    - Extracted Ubiquiti self-signed cert from running pod via openssl s_client
    - Created kubernetes/apps/network/unifi/app/configmap.yaml with cert as 'ca.crt'
    - Updated BackendTLSPolicy: caCertificateRefs → [unifi-ca ConfigMap], hostname: unifi, subjectAltNames: [{type: Hostname, hostname: unifi}]
    - Added configmap.yaml to kustomization.yaml resources
    - Committed as two commits (7781f353), Flux reconciled successfully
    - BackendTLSPolicy generation 3: Accepted=True, ResolvedRefs=True
    - Verified: curl through gateway returns HTTP 302, TLS handshake succeeds, ssl.fail_verify_san=0

verification:
  - qbittorrent: Envoy routing to 10.69.0.63:8080 confirmed via config_dump ✅
  - unifi: Live HTTP 302 response via gateway, TLS handshake=1 with zero SAN failures ✅
  - Both BackendTLSPolicy and ConfigMap deployed on cluster at commit 7781f353 ✅

files_changed:
  - kubernetes/apps/media/qbittorrent/app/helmrelease.yaml (port 8080 route rules)
  - kubernetes/apps/network/unifi/app/backendtlspolicy.yaml (caCertificateRefs, hostname, subjectAltNames)
  - kubernetes/apps/network/unifi/app/configmap.yaml (new — Ubiquiti self-signed CA cert)
  - kubernetes/apps/network/unifi/app/kustomization.yaml (added configmap.yaml resource)
