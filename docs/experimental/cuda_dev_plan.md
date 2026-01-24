# CUDA Support Development Plan

This document defines a phased step-by-step plan to implement and validate CUDA support for Zeropod, specifically targeting vLLM workloads.
Each phase is designed to be developed and validated in isolation before moving to the next.

## Phase 1: Installer & Environment

**Goal**: Ensure the `cuda-checkpoint` binary is available on the host node in a known location accessible by Zeropod.

### Implementation Steps
1.  **Modify `cmd/installer/main.go`**:
    -   Add logic to check if `cuda-checkpoint` exists on the host (e.g., in `/usr/bin/` or `/usr/local/bin/`).
    -   *Alternative*: If we can bundle `cuda-checkpoint`, extend the `zeropod-installer` image to include it and copy it to `/opt/zeropod/bin/` alongside `criu`.
    -   Ensure `/opt/zeropod/bin` is in the `PATH` or the shim knows to look there.

### Test Scenario
1.  **Build**: `make build-installer`
2.  **Deploy to MicroK8s**:
    -   Export image: `docker save ghcr.io/ctrox/zeropod-installer:dev -o installer.tar`
    -   Import to MicroK8s: `microk8s ctr image import installer.tar`
    -   **Important**: Ensure the installer DaemonSet is configured with `-runtime=microk8s` and the correct socket path (e.g., `/var/snap/microk8s/common/run/containerd.sock`).
3.  **Verification Command**:
    ```bash
    # On the MicroK8s node
    ls -l /opt/zeropod/bin/cuda-checkpoint
    /opt/zeropod/bin/cuda-checkpoint --version
    ```
4.  **Success Criteria**: The binary is present and executable.

---

## Phase 2: vLLM Test Workload & Cgroup Detection

**Goal**: Deploy a real CUDA workload (vLLM) and verify we can reliably identify its Process IDs (PIDs) from the host using Cgroups.

### Resources
**`e2e/cuda/vllm.yaml`**:
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: vllm-inference
  labels:
    app: vllm
  annotations:
    zeropod.ctrox.dev/scaledown-duration: "1h" # Disable auto-scale for now
spec:
  runtimeClassName: zeropod
  containers:
  - name: vllm
    image: vllm/vllm-openai:latest
    args: ["--model", "facebook/opt-125m"]
    resources:
      limits:
        nvidia.com/gpu: "1"
    env:
      - name: NVIDIA_VISIBLE_DEVICES
        value: "all"
```

### Implementation Steps
1.  **Deploy vLLM**: `microk8s kubectl apply -f e2e/cuda/vllm.yaml`
2.  **Manual Cgroup Inspection**:
    -   Locate the Cgroup on the host: `find /sys/fs/cgroup -name "*vllm*"`
    -   Read PIDs: `cat .../cgroup.procs`
3.  **Shim Prototype (Manual Test)**:
    -   Write a temporary Go script (or test in `shim/`) that takes a Container ID.
    -   Uses `shim.GetNetworkNS` or `cgroup` paths to finding the `cgroup.procs`.
    -   Prints the PIDs.

### Test Scenario
1.  Start vLLM pod.
2.  Wait for it to load model (CUDA memory usage > 0).
3.  Run detection script.
4.  **Success Criteria**: Script output matches `ps -ef | grep vllm`.

---

## Phase 3: Isolated CUDA Suspend/Resume

**Goal**: Verify `cuda-checkpoint` works on the running vLLM process *without* CRIU.

### Implementation Steps
1.  **Develop `cmd/debug-tool` (Temporary)**:
    -   A specialized tool that:
        1.  Accepts a list of PIDs (from Phase 2).
        2.  Iterates and runs `cuda-checkpoint --suspend --pid <PID>`.
        3.  Waits for user input.
        4.  Runs `cuda-checkpoint --resume --pid <PID>`.

### Test Scenario
1.  Start vLLM pod. Send a request to verify it works.
2.  Run `debug-tool` against vLLM PIDs.
3.  **Verify Suspension**:
    -   Check `nvidia-smi`. GPU utilization should drop to 0% (or near 0).
    -   Memory might be evicted (depending on driver version/flags).
    -   vLLM should stop responding to requests (but TCP might hang).
4.  Trigger Resume in `debug-tool`.
5.  **Verify Resumption**:
    -   Send a request. It should answer without crashing.
    -   No "CUDA unknown error" in logs.

---

## Phase 4: Zeropod Shim Integration (The Real Deal)

**Goal**: Integrate the logic into the automatic Scaledown/Scaleup loop.

### Implementation Steps
1.  **Modify `shim/checkpoint.go`**:
    -   Inject the "Suspend Loop" (from Phase 3) *before* `runc.Checkpoint`.
    -   Ensure `cuda-checkpoint` is called with metadata (e.g., where to dump VRAM if needed, though usually it manages itself).
2.  **Modify `shim/restore.go`**:
    -   Inject any necessary "Resume Loop" *after* `runc.Restore`.
    -   (Note: `cuda-checkpoint` usually hooks into the process, so explicit resume might not be needed if CRIU restores the memory image correctly, but this must be verified).

### Test Scenario (End-to-End)
1.  Deploy vLLM with `scaledown-duration: "10s"`.
2.  Send request -> **Success**.
3.  Wait 10s.
4.  **Verify Scaledown**:
    -   Logs show `cuda-checkpoint --suspend` success.
    -   Logs show `runc checkpoint` success.
    -   Pod status: `SCALED_DOWN`.
5.  Send request (Trigger Activate).
6.  **Verify Scaleup**:
    -   Logs show restore.
    -   Request completes successfully.
    -   Latencies are measured.

---

## Required Resources Checklist

- [ ] GPU Node (NVIDIA Driver >= 550)
- [ ] `cuda-checkpoint` binary
- [ ] vLLM Docker Image (compatible with host CUDA version)
- [ ] Zeropod Development Environment
