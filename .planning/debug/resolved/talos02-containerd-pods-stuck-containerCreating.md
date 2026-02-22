---
status: resolved
trigger: "Pods scheduled to talos02 get stuck in ContainerCreating with no events beyond Scheduled, while talos01 and talos03 are healthy."
created: 2026-02-22T00:00:00Z
updated: 2026-02-22T11:12:00Z
---

## Current Focus

hypothesis: Disk I/O contention on talos02 — Ceph OSD (id 2) + Ceph Mon running on same disk as etcd, plus Prometheus TSDB and Frigate video recording; Ceph daemon sockets unresponsive to health checks (>5s), causing kubelet ExecSync timeouts which block goroutine pool; etcd slow fdatasync (1s+) from same disk contention
test: Defrag completed on all 3 nodes (talos01=100%, talos03=100%, talos02=98%); talos01 etcd latency dropped to <100ms after defrag (last slow warning 11:00:27, no new ones); but talos02 etcd still shows slow fdatasync and kubelet stuck on Ceph ExecSync — structural disk contention persists
expecting: Defrag was necessary to fix fragmentation on talos01/talos03 but insufficient for talos02's disk I/O contention; deeper fix requires Ceph I/O isolation from etcd
next_action: Document findings and open new investigation for talos02 disk contention (Ceph vs etcd on same disk)

## Symptoms

expected: Pods scheduled to talos02 should start normally, pull images, and reach Running state
actual: Pods scheduled to talos02 get stuck in ContainerCreating indefinitely; no events appear beyond the initial "Scheduled" event
errors: |
  kubelet: "MountVolume.SetUp failed for volume 'kube-api-access-...' : failed to fetch token: Timeout: request did not complete within requested timeout - context deadline exceeded"
  kube-apiserver: "Timeout or abort while handling", "apiserver was unable to write a JSON response: http: Handler timeout"
  kube-apiserver: "Resetting endpoints for master service 'kubernetes' to [10.20.0.14 10.20.0.16]" (drops talos02)
  etcd: "waiting for ReadIndex response took too long, retrying"
  etcd: "apply request took too long" (144ms–960ms, expected <100ms)
  etcd: "finished scheduled compaction" took 2.28 seconds
  kube-scheduler-talos02: "handlers are not fully synchronized" err="context canceled" (crash-looping, 468 restarts over 44h)
  kubelet healthz: "Get 'http://127.0.0.1:10248/healthz': context deadline exceeded"
reproduction: Schedule any pod to talos02; it never transitions out of ContainerCreating
started: talos02 was joined ~44 hours ago; kube-scheduler has been crash-looping since join

## Eliminated

- hypothesis: containerd on talos02 is broken
  evidence: containerd logs are clean — healthy startup, no errors, no failed image pulls
  timestamp: 2026-02-22T01:00:00Z

- hypothesis: CNI (Cilium) is broken on talos02
  evidence: CiliumNode shows CiliumIsUp on all 3 nodes; Cilium pod on talos02 is Running
  timestamp: 2026-02-22T01:00:00Z

- hypothesis: Volume attach/mount (CSI) is broken on talos02
  evidence: RBD volumes attach and stage correctly; the blockdevice is accessible; CSI itself is not the blocker
  timestamp: 2026-02-22T01:00:00Z

- hypothesis: Node is NotReady or has resource pressure
  evidence: All 3 nodes show Ready with no memory/disk/PID pressure conditions
  timestamp: 2026-02-22T01:00:00Z

## Evidence

- timestamp: 2026-02-22T01:00:00Z
  checked: kube-scheduler-talos02 pod
  found: 468 restarts over 44 hours; logs show it starts, syncs caches, then after ~70s hits "handlers are not fully synchronized" err="context canceled" and exits
  implication: kube-scheduler on talos02 is broken but irrelevant for scheduling (leader is talos01); symptom of unstable local apiserver

- timestamp: 2026-02-22T01:00:00Z
  checked: kube-apiserver-talos02 logs
  found: Repeated "DeadlineExceeded" from etcd client, handler timeouts, apiserver periodically removes talos02 from kubernetes service endpoints
  implication: kube-apiserver on talos02 is unreliable due to slow etcd responses

- timestamp: 2026-02-22T01:05:00Z
  checked: kubelet logs on talos02
  found: "MountVolume.SetUp failed for volume 'kube-api-access-...' : failed to fetch token: Timeout" — projected SA token volume mount fails because kubelet's call to apiserver times out
  implication: This is the direct cause of ContainerCreating hang — pods can't get their SA token mounted

- timestamp: 2026-02-22T01:10:00Z
  checked: etcd logs on talos02
  found: "waiting for ReadIndex response took too long, retrying" (multiple per minute); "apply request took too long" (144ms–960ms); compaction took 2.28s; DB size 469MB allocated / 71MB in use (85% fragmentation)
  implication: etcd is severely fragmented and slow — ROOT CAUSE. All other failures cascade from this.

- timestamp: 2026-02-22T01:15:00Z
  checked: talosctl service kubelet on talos02
  found: Intermittent healthz timeout "Get 'http://127.0.0.1:10248/healthz': context deadline exceeded"
  implication: Confirms kubelet is overloaded/blocked, likely waiting on apiserver calls that time out

- timestamp: 2026-02-22T01:20:00Z
  checked: volsync-src-photoprism-gsvtg stuck pod
  found: VolumePermissionChangeInProgress — kubelet is recursively chowning 500k+ files on large RBD volume; 565,718 files processed and still running
  implication: Secondary cause of ContainerCreating for photoprism pod specifically; fix requires fsGroupChangePolicy: OnRootMismatch

- timestamp: 2026-02-22T10:38:00Z
  checked: kubectl top nodes + talosctl processes (CPU-sorted)
  found: metrics-server shows talos02 CPU as <unknown> (metrics-server can't reach it); talosctl processes shows etcd (67k CPU-s), cilium (43k), kube-apiserver (37k), containerd (35k), frigate+ffmpeg (~30k total) as top consumers by cumulative CPU time
  implication: Cumulative CPU-time figures reflect node age; current CPU rate unknown from kubectl top, but etcd and apiserver are primary suspects for elevated load

- timestamp: 2026-02-22T10:39:00Z
  checked: talosctl etcd status (all 3 nodes)
  found: talos02=87MB/56MB(64% frag), talos01=467MB/55MB(88% frag), talos03=467MB/55MB(88% frag); LEADER is talos01 (25e10c575a763da7)
  implication: talos02 was already defragged at some point; talos01 (leader) and talos03 are still at 88% fragmentation — ALL linearizable reads require round-trip through the leader, so talos01's fragmentation directly causes slow etcd responses on ALL nodes including talos02

- timestamp: 2026-02-22T10:39:30Z
  checked: etcd logs on talos02 (current)
  found: Still seeing "apply request took too long" (130ms–590ms) with "agreement among raft nodes before linearized reading" steps taking 26–467ms — the raft round-trip to the leader is the bottleneck
  implication: talos02's etcd defrag alone did not fix latency because the leader (talos01) is still fragmented; must defrag talos01 and talos03

- timestamp: 2026-02-22T10:40:00Z
  checked: kube-scheduler-talos02 describe + logs
  found: 585 restarts; liveness probe fails with "context deadline exceeded" (https://localhost:10259/livez); readyz fails "context deadline exceeded"; scheduler starts, tries leader election (doesn't win), then livez times out after ~2min and kubelet kills it
  implication: kube-scheduler crash-loop is a SYMPTOM not a cause — scheduler's /livez endpoint relies on apiserver calls which time out due to slow etcd on leader; fixing etcd fragmentation on talos01/talos03 should stabilize this

- timestamp: 2026-02-22T11:00:03Z
  checked: talosctl etcd defrag --nodes 10.20.0.16 (talos03) then --nodes 10.20.0.14 (talos01)
  found: talos03 defrag: 467MB→57MB (100% clean); talos01 was already ~60MB when defrag ran (compaction had caught up), defrag brought to 57MB (100%); talos02 at 60MB/58MB (98%); all 3 nodes now healthy; raft term stayed 195 (no leader election)
  implication: Fragmentation on talos01/talos03 was successfully resolved; last slow request on talos01 was 11:00:27 (~24s after defrag), after which etcd on talos01 went clean

- timestamp: 2026-02-22T11:06:00Z
  checked: etcd logs on talos02 (post-defrag); kubelet logs on talos02
  found: etcd on talos02 still showing "slow fdatasync" (1.007s) and "apply request took too long" (115ms–1.877s) and "waiting for ReadIndex response took too long"; kubelet repeatedly timing out on ExecSync for "ceph-osd.2.asok status" and "ceph-mon.c.asok mon_status" (>5s each, continuous)
  implication: The disk I/O contention on talos02 is structural — Ceph OSD (id 2) + Ceph Mon + Prometheus TSDB (50GB, 2GB RAM) + Frigate video recording all share the same disk as etcd; Ceph daemon sockets unresponsive because the OSD is I/O saturated; defrag fixed DB layout but not disk bandwidth exhaustion

- timestamp: 2026-02-22T11:07:00Z
  checked: talosctl processes on talos02 sorted by CPU
  found: ceph-osd (pid 93688, 875 CPU-s), prometheus (76478, 1439 CPU-s, 2GB RAM), promtail (74120, 955 CPU-s), frigate (74623 ffmpeg, 666 CPU-s), ceph-exporter (6658, 9174 CPU-s), cilium-agent (7356, 43884 CPU-s)
  implication: talos02 is heavily loaded with I/O-intensive workloads that landed on it when it joined 44h ago; these compete with etcd for disk I/O bandwidth; Ceph OSD on same disk as etcd is the primary contention source

## Resolution

root_cause: |
  TWO-LAYER ROOT CAUSE:

  Layer 1 (FIXED): etcd on talos01 (leader) and talos03 had severe fragmentation (467MB allocated / 55MB in use = ~88%).
  Since ALL linearizable reads require a raft round-trip to the leader, talos01's fragmented disk caused slow etcd
  responses across ALL nodes (150-960ms vs expected <100ms). This caused: kube-apiserver-talos02 timeouts,
  kubelet SA token fetch failures (ContainerCreating hang), kube-scheduler crash-loop (585+ restarts),
  metrics-server scrape failures (<unknown>).

  Layer 2 (OPEN): Even after defrag, talos02's etcd has "slow fdatasync" (1s+) due to Ceph OSD (id 2) + Ceph Mon
  + Prometheus (50GB TSDB) + Frigate video recording all sharing the same disk as etcd.
  Kubelet goroutines are blocked on Ceph ExecSync health checks (>5s timeout, continuous) preventing metrics-server
  response. This is disk I/O contention, not solvable by defrag alone.

  Secondary: volsync-src-photoprism blocked by recursive fsGroup chown on 500k+ file RBD volume.

fix: |
  COMPLETED: Defragmented etcd on talos03 (10.20.0.16) and talos01 (10.20.0.14)
    - talosctl etcd defrag --nodes 10.20.0.16  → 467MB → 57MB (100% clean)
    - talosctl etcd defrag --nodes 10.20.0.14  → 60MB → 57MB (100% clean)
    - talos02 (10.20.0.15): 60MB/58MB (98% clean) from prior defrag
    - Raft term unchanged (195) — no leader election triggered
    - talos01 etcd slow warnings stopped at 11:00:27, none after

  PENDING: Resolve talos02 disk I/O contention:
    Option A: Move Ceph OSD data to dedicated NVMe partition separate from etcd WAL
    Option B: Tune Ceph OSD bluestore_cache_size / throttling to reduce disk pressure
    Option C: Move Prometheus and/or Frigate off talos02 via node affinity rules

  PENDING: Add fsGroupChangePolicy: OnRootMismatch to photoprism app

verification: |
  PARTIAL VERIFICATION:
  ✅ talos01 etcd: 57MB/57MB (100%), no slow warnings since 11:00:27 (post-defrag clean)
  ✅ talos03 etcd: 57MB/57MB (100%), healthy
  ✅ talos02 etcd: 60MB/58MB (98%), fragmentation resolved
  ✅ Raft term stable at 195, leader remains talos01 — no disruption
  ✅ kube-apiserver-talos02: 1/1 Running, only 2 total restarts (no new restarts during fix)
  ❌ kube-scheduler-talos02: 594 restarts, still CrashLoopBackOff — disk contention on talos02
     still causing apiserver timeouts; scheduler /livez probe still timing out
  ❌ kubectl top nodes talos02: still <unknown> — metrics-server still timing out on kubelet
     scrape (kubelet blocked on Ceph ExecSync health checks)
  ❌ etcd on talos02: still shows slow fdatasync (1s+) — disk I/O contention with Ceph OSD

  The defrag successfully resolved the fragmentation issue on talos01/talos03 (the original
  root cause identified). However, talos02 has an additional underlying disk I/O contention
  problem that requires a separate fix.

  PRIMARY SYMPTOM STATUS (ContainerCreating hang):
  ✅ 22 pods Running on talos02, 0 pods stuck in ContainerCreating
  ✅ node-exporter CrashLoopBackOff is pre-existing (35 days old), unrelated
  The defrag on talos01 was sufficient to stop the SA token fetch timeouts even though
  talos02's local etcd is still slow — the leader defrag reduced raft round-trip times
  enough to unblock kubelet token requests.
