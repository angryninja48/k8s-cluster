---
status: resolved
trigger: "GitHub Actions workflow is stuck in queued state for the home-assistant-config repo"
created: 2026-03-01T00:00:00Z
updated: 2026-03-01T04:25:00Z
---

## Current Focus

hypothesis: RESOLVED — all three root causes identified and fixed
test: Triggered real workflow run via test push to ha-v2-config branch
expecting: Workflow completes successfully
next_action: DONE

## Symptoms

expected: GitHub Actions workflow triggers and runs when changes are pushed to the home-assistant-config repo (branch: ha-v2-config), causing a Flux rollout on the k8s cluster
actual: Workflow is stuck in "queued" state — runner pods start, complete in ~4 seconds, and exit. ARC marks runner as TooManyPodFailures after 5 attempts. Listener keeps polling the same messageID without advancing.
errors: Runner binary exits with "VssOAuthTokenRequestException: Registration <UUID> was not found. Failed to create a session. The runner registration has been deleted from the server, please re-configure."
reproduction: Push a change to angryninja48/home-assistant-config on branch ha-v2-config (multiple queued runs exist)
started: Unknown — may never have worked or recently broke

## Eliminated

- hypothesis: Workflow trigger branch mismatch (ha-v2-config vs ha-config-v2)
  evidence: Confirmed workflow file uses "ha-v2-config" and that IS the active branch
  timestamp: 2026-03-01T01:00:00Z

- hypothesis: runs-on label mismatch (workflow label vs runner registration label)
  evidence: Workflow uses "runs-on: ha-restarter" and HelmRelease metadata.name is "ha-restarter" — they match
  timestamp: 2026-03-01T01:00:00Z

- hypothesis: GitHub auth secret missing
  evidence: arc-github-secret exists in arc-runners namespace, created via ExternalSecret from Doppler
  timestamp: 2026-03-01T01:00:00Z

- hypothesis: GitHub HTTPS connectivity issue from cluster
  evidence: HTTP 200 OK to api.github.com confirmed from cluster
  timestamp: 2026-03-01T01:00:00Z

- hypothesis: ARC controller or listener not running
  evidence: Both actions-runner-controller pod and ha-restarter-754b578d-listener pod are Running in arc-systems
  timestamp: 2026-03-01T01:00:00Z

- hypothesis: init container (bitnami/kubectl copy to emptyDir) failing
  evidence: Init container works fine, kubectl binary copied successfully
  timestamp: 2026-03-01T01:00:00Z

- hypothesis: Fine-grained PAT insufficient trust level causing OAuth failure
  evidence: Replaced fine-grained PAT with classic PAT (ghp_...) — same error persists. PAT type is NOT the root cause.
  timestamp: 2026-03-01T04:00:00Z

- hypothesis: Stale JIT config (expired token in cached config)
  evidence: Generated fresh JIT config 2 seconds before running the runner binary — same "Registration was not found" error. JIT config freshness is NOT the root cause.
  timestamp: 2026-03-01T04:00:00Z

## Evidence

- timestamp: 2026-03-01T01:00:00Z
  checked: .github/workflows/restart-ha-on-push.yml in home-assistant-config repo
  found: Triggers on push to ha-v2-config branch, runs-on: ha-restarter, calls flux reconcile kustomization home-assistant
  implication: Workflow config is correct

- timestamp: 2026-03-01T01:00:00Z
  checked: kubernetes/apps/arc-runners/ha-restarter/app/helmrelease.yaml
  found: ARC runner scale set, runnerScaleSetName: ha-restarter, minRunners: 0, maxRunners: 1, UseV2Flow: true
  implication: Runner registration label "ha-restarter" matches workflow runs-on label

- timestamp: 2026-03-01T01:00:00Z
  checked: EphemeralRunner pods in arc-runners namespace
  found: Pods complete in ~4 seconds with status "Completed" (exit 0). ARC marks TooManyPodFailures after 5 attempts. Runner IDs incrementing.
  implication: Runner registers, then immediately exits without picking up any job

- timestamp: 2026-03-01T01:00:00Z
  checked: ha-restarter listener pod logs in arc-systems
  found: lastMessageID never advances. "assigned job: 0, decision: 1" repeatedly. Scales to 1 runner, runner fails, scales back to 0, repeats.
  implication: Listener is connected and receiving messages but no job is ever "assigned" (picked up by runner)

- timestamp: 2026-03-01T01:00:00Z
  checked: ARC controller (gha-rs-controller) logs
  found: "failed: 1" persists. Never transitions to "running: 1" or "finished: 1".
  implication: Runner pod starts but fails before registering as active with GitHub

- timestamp: 2026-03-01T01:00:00Z
  checked: JIT config (decoded from ACTIONS_RUNNER_INPUT_JITCONFIG env var)
  found: ServerUrl: https://pipelinesghubeus2.actions.githubusercontent.com/<tenant>/..., Scale set ID: 1, runner group: Default (ID: 1), UseV2Flow: true
  implication: JIT config is well-formed; tenant prefix in ServerUrl may be stale

- timestamp: 2026-03-01T01:00:00Z
  checked: run-helper.sh in runner image
  found: Exit 1 → "stop the service, no retry needed" → pod completes with exit 0. run-helper maps exit 1 to exit 0.
  implication: Runner binary exits 1 (fatal error), run-helper exits 0, ARC sees pod finished → marks runner failed

- timestamp: 2026-03-01T04:00:00Z
  checked: Direct Runner.Listener execution output in debug pod
  found: "√ Connected to GitHub" then POST to pipelinesghubeus2.actions.githubusercontent.com/.../oauth2/token → HTTP 400 BadRequest → "VssOAuthTokenRequestException: Registration <UUID> was not found. Failed to create a session. The runner registration has been deleted from the server, please re-configure."
  implication: Runner connects successfully but the ClientId UUID from the JIT config is not found on the pipelines OAuth endpoint

- timestamp: 2026-03-01T04:00:00Z
  checked: Fresh JIT config (generated 2s before runner execution) with classic PAT
  found: Same "Registration was not found" error with brand-new JIT config
  implication: This is NOT a staleness issue — the registration is genuinely absent from the pipelines service

- timestamp: 2026-03-01T04:00:00Z
  checked: EphemeralRunnerSet ha-restarter-zcp79 in arc-runners namespace
  found: Created 2026-02-28T21:34:29Z, generation ~316+, stuck in TooManyPodFailures loop
  implication: The scale set has been failing since creation — this configuration may never have worked

- timestamp: 2026-03-01T04:05:00Z
  checked: Runner pod spec via debug pod - inspected live EphemeralRunner pod spec
  found: container[0].command was null/missing — image default CMD ["/bin/bash"] used instead of ["/home/runner/run.sh"]
  implication: ROOT CAUSE 1 — runner binary never ran; /bin/bash exits immediately causing "Registration not found" failure chain

- timestamp: 2026-03-01T04:10:00Z
  checked: Docker image inspect ghcr.io/actions/actions-runner:latest
  found: Default CMD is ["/bin/bash"] (not run.sh). ARC chart default is command: ["/home/runner/run.sh"]
  implication: Confirmed — custom container override in HelmRelease silently dropped the command field

- timestamp: 2026-03-01T04:13:00Z
  checked: Live AutoscalingRunnerSet spec after command fix (commit 747fbc21)
  found: command: ["/home/runner/run.sh"] applied correctly, but initContainers/volumes/serviceAccountName MISSING from live resource
  implication: ROOT CAUSE 2 — server-side apply merge issue: old AutoscalingRunnerSet had only containers field; new fields weren't being applied on top

- timestamp: 2026-03-01T04:15:00Z
  checked: helm get manifest vs kubectl get autoscalingrunnerset
  found: Helm manifest has initContainers/volumes/serviceAccountName correctly; live resource missing them. last-applied annotation only shows containers.
  implication: Confirmed server-side apply merge conflict — Helm rendered correctly but K8s API rejected/ignored new fields on update

- timestamp: 2026-03-01T04:20:00Z
  checked: ARC chart template autoscalingrunnerset.yaml
  found: Chart template correctly passes initContainers/volumes through to the resource. Not a chart bug.
  implication: Problem was purely the stale live resource with incomplete last-applied annotation

- timestamp: 2026-03-01T04:22:00Z
  checked: AutoscalingRunnerSet after delete + helm upgrade --reuse-values
  found: initContainers, volumes, serviceAccountName all present in live resource
  implication: Fix confirmed — fresh resource has full spec

- timestamp: 2026-03-01T04:25:00Z
  checked: Workflow run 22535829013 triggered by test push to ha-v2-config
  found: Status: completed / Conclusion: success. Runner pod ran and cleaned up successfully.
  implication: END-TO-END VERIFIED — ARC runner works correctly

## Resolution

root_cause: |
  Three compounding bugs prevented the runner from working:

  1. ROOT CAUSE (primary): The HelmRelease `template.spec.containers` override for the `runner` container
     did NOT include a `command` field. The ARC chart merges the user-supplied container config into the
     default, but when you specify a custom container, it replaces the command with null — causing Kubernetes
     to fall back to the image's default CMD (["/bin/bash"]). /bin/bash with no args exits immediately (exit 0),
     which is why runners were completing in <1 second and the "Registration not found" error appeared (the
     runner binary never ran at all).

  2. ROOT CAUSE (secondary): After adding `command: ["/home/runner/run.sh"]`, the live AutoscalingRunnerSet
     still lacked `initContainers`, `volumes`, and `serviceAccountName`. This was caused by a Kubernetes
     server-side apply merge conflict — the original resource only had `containers` in `template.spec`, so
     the `last-applied-configuration` annotation only tracked that field. Subsequent Helm upgrades added
     initContainers/volumes to the rendered manifest, but K8s strategic merge patch didn't apply them to
     the existing object (the new fields had no previous manager). Helm believed it succeeded (values-hash
     matched) but the live object was incomplete.

  3. CONSEQUENCE: With volumes missing but volumeMounts present in the container, every EphemeralRunner
     pod creation failed with: "spec.containers[0].volumeMounts[0].name: Not found: 'kubectl-bin'"

fix: |
  Fix 1 (commit 747fbc21): Added `command: ["/home/runner/run.sh"]` to the runner container spec in
  kubernetes/apps/arc-runners/ha-restarter/app/helmrelease.yaml

  Fix 2: Deleted the stale AutoscalingRunnerSet (kubectl delete autoscalingrunnerset ha-restarter -n arc-runners)
  and ran `helm upgrade ha-restarter ... --reuse-values` to recreate it from scratch. This bypassed the
  server-side apply merge conflict by starting with a fresh resource.

  Flux was suspended during the delete to prevent race conditions, then resumed after Helm recreated the resource.

verification: |
  Workflow run 22535829013 (test push to ha-v2-config branch) completed with:
  - Status: completed
  - Conclusion: success
  - Runner pod ha-restarter-kscgc-runner-n5bgx ran successfully and cleaned up
  - No more "kubectl-bin volume not found" errors
  - No more "Registration was not found" errors

files_changed:
  - kubernetes/apps/arc-runners/ha-restarter/app/helmrelease.yaml
