# Zeropod Component Interactions

This document details the low-level interactions between the Zeropod components: the Containerd Shim, the Activator, the Manager, and the underlying Linux Kernel technologies (CRIU, eBPF).

## High-Level Component View

The following diagram illustrates the relationship between the components on a single node.

```
                                      +---------------------+
                                      |    K8s API Server   |
                                      +----------+----------+
                                                 |
                                      +----------v----------+
                                      |       Kubelet       |
                                      +----------+----------+
                                                 |
                                      +----------v----------+
                                      |     Containerd      |
                                      +----+-----------+----+
                                           |           |
                        +------------------v-----------v------------------+
                        |           Zeropod Shim (per Pod)                |
                        | +---------------------------------------------+ |
                        | |                Main Loop                    | |
                        | |  - Metrics                                  | |
                        | |  - Scaling Logic                            | |
                        | +--------+-------------------------+----------+ |
                        |          |                         |            |
                        |   +------v-------+          +------v------+     |
                        |   |  Activator   |          |    RunC     |     |
                        |   | (subprocess) |          | (lib/exec)  |     |
                        |   +------+-------+          +------+------+     |
                        |          |                         |            |
                        +----------|-------------------------|------------+
                                   |                         |
                                   |                         |
+----------------------------------|-------------------------|--------------------------------+
| Kernel Space                     |                         |                                |
|                                  |                         |                                |
|   +-------------------+    +-----v------+           +------v-------+                        |
|   |   eBPF Program    |<---| Network    |           |  Container   |                        |
|   | (Traffic Redirect)|    | Namespace  |           |  Processes   |                        |
|   +-------------------+    +------------+           +--------------+                        |
|                                                                                             |
+---------------------------------------------------------------------------------------------+
                                   ^
                                   |
                         +---------v----------+
                         |   Zeropod Manager  |
                         |     (DaemonSet)    |
                         +--------------------+
```

## Detailed Interaction Flows

### 1. Scale Down (Checkpointing)

The scale-down process is triggered when the Shim detects no network activity for a configured duration.

**Pre-requisites:**
- Container is running.
- `lastActivity` tracking in Shim (via eBPF map checks) shows threshold exceeded.

**Flow:**

```
      Shim                  Activator               Manager                 CRIU                   Container
        |                       |                      |                      |                        |
        | [1] Check Activity    |                      |                      |                        |
        |---------------------->|                      |                      |                        |
        |                       |                      |                      |                        |
        | [2] No Activity?      |                      |                      |                        |
        |<----------------------|                      |                      |                        |
        |                       |                      |                      |                        |
        | [3] Schedule Scale Down                      |                      |                        |
        |-----------------------|                      |                      |                        |
        |                       |                      |                      |                        |
        | [4] Start Activator (Listener)               |                      |                        |
        |---------------------->|                      |                      |                        |
        |                       | bind(port)           |                      |                        |
        |                       | listen()             |                      |                        |
        |                       |<---------------------|                      |                        |
        |                       |                      |                      |                        |
        | [5] Register Redirect |                      |                      |                        |
        |---------------------->|                      |                      |                        |
        |                       | Update eBPF Map      |                      |                        |
        |                       | (Traffic -> Activator)|                     |                        |
        |                       |--------------------->|                      |                        |
        |                       |                      |                      |                        |
        | [6] Checkpoint        |                      |                      |                        |
        |-----------------------|----------------------|--------------------->|                        |
        |                       |                      |                      | Dump process state     |
        |                       |                      |                      |----------------------->|
        |                       |                      |                      | Stop process           |
        |                       |                      |                      |----------------------->X
        |                       |                      |                      | Write images to disk   |
        |                       |                      |                      |<-----------------------|
        | [7] Update Status     |                      |                      |                        |
        |-----------------------|--------------------->|                      |                        |
        |                       |   Set Label/Event    |                      |                        |
        |                       |                      |                      |                        |
```

**Step-by-Step Explanation:**
1.  **Activity Check**: The Shim periodically queries the `Activator` (or checks shared maps) to see the last time a packet was seen.
2.  **Decision**: If `time.Now() - lastActivity > threshold`, the Shim decides to scale down.
3.  **Start Activator**: Before killing the container, the Shim ensures the `Activator` is running and listening on a random high port.
4.  **Register Redirect**: The `Activator` updates the eBPF maps managed by the `Manager`. It sets a rule: "Any traffic destined for port 80 (Container) should be redirected to port X (Activator)".
5.  **Checkpoint**: The Shim invokes `runc checkpoint` (which calls `criu dump`). The container processes are frozen and their memory/state is written to disk (tmpfs or persistent volume).
6.  **Update Status**: The Shim notifies the Manager via the node service API that the pod is now `SCALED_DOWN`. The Manager updates Kubernetes Pod labels/events.

### 2. Scale Up (Restoration)

The scale-up process is instantaneous (from the user's perspective 50-200ms) and is triggered by an incoming TCP packet.

**Flow:**

```
      User                  eBPF / Kernel            Activator                Shim                   CRIU
        |                        |                       |                      |                      |
        | [1] TCP SYN (Port 80)  |                       |                      |                      |
        |----------------------->|                       |                      |                      |
        |                        | [2] Redirect to       |                      |                      |
        |                        |      Activator (Port X)|                     |                      |
        |                        |---------------------->|                      |                      |
        |                        |                       | [3] Accept Connection|                      |
        |                        |                       |--------------------->|                      |
        |                        |                       |                      |                      |
        |                        |                       | [4] Trigger Restore  |                      |
        |                        |                       |--------------------->|                      |
        |                        |                       |                      | [5] Restore          |
        |                        |                       |                      |--------------------->|
        |                        |                       |                      |                      | Load images
        |                        |                       |                      |                      | Restore Process
        |                        |                       |                      |                      | Start Container
        |                        |                       |                      |                      |<-------------
        |                        |                       |                      | <--------------------|
        |                        |                       | [6] Disable Redirect |                      |
        |                        |                       | (Remove eBPF rule)   |                      |
        |                        |                       |--------------------->|                      |
        |                        |                       |                      |                      |
        |                        |                       | [7] Proxy Traffic    |                      |
        |                        |                       |----------------------|--------------------->|
        |                        |                       |                      |                      |
    <---------------------------------------------------|----------------------|---------------------| (Response)
        |                        |                       |                      |                      |
        | [8] Subsequent Packets |                       |                      |                      |
        |----------------------->|                       |                      |                      |
        |                        | [9] Pass-through      |                      |                      |
        |                        |-----------------------|----------------------|--------------------->|
        |                        |                       |                      |                      |
```

**Step-by-Step Explanation:**
1.  **Incoming Traffic**: A user sends a request to the application.
2.  **eBPF Redirect**: The kernel networking stack sees the packet. The eBPF program (loaded by Manager, configured by Activator) identifies it matches a scaled-down service and changes the destination to the Activator's listening port.
3.  **Accept & Hold**: The Activator accepts the TCP connection. It *holds* the connection open but does not send data yet. It typically peeks at the data to identify protocols if needed.
4.  **Trigger Restore**: The Activator signals the Shim (via a channel or callback) that a wake-up is required.
5.  **Restore**: The Shim invokes `runc restore` (CRIU). The container processes are read from disk and resumed **exactly** where they left off.
    > [!NOTE]
    > This is a **true process resume** (stateful), not a cold start. All memory contents, file descriptors, and execution states are restored. It is analogous to waking a laptop from sleep, rather than rebooting it.
6.  **Disable Redirect**: Once the container is running and ready (verified by a quick connectivity check or immediate resumption), the Activator removes the eBPF redirect rule. New connections will now go directly to the container.
7.  **Proxy & Handover**: For the *initial* connection that triggered the wake-up, the Activator proxies the data to the now-running container application. This ensures the first packet isn't dropped.
8.  **Direct Path**: All subsequent connections bypass the Activator entirely, ensuring zero overhead for active workloads.

### 3. Node Migration (Evacuation)

Migration allows a running (or scaled down) pod to move to another node without losing state. Crucially, this involves **Peer-to-Peer (P2P)** data transfer between Zeropod Managers, coordinated via Kubernetes Custom Resources.

**Flow:**

```
      Source Node                            Kubernetes API                          Destination Node
     (Shim + Manager)                               |                                (Shim + Manager)
           |                                        |                                        |
           | [1] Evacuate (Signal/API)              |                                        |
    [Shim]-+--------------------------------------->|                                        |
           |                                        |                                        |
           | [2] Create Migration CRD               |                                        |
    [Mgr]--+--------------------------------------->|                                        |
           |   (Status: Pending)                    |                                        |
           |                                        |                                        |
           | [3] Checkpoint Container               |                                        |
    [Shim]-+-----> [CRIU Dump]                      |                                        |
           |                                        |                                        |
           | [4] Update Migration CRD               |                                        |
    [Mgr]--+--------------------------------------->|                                        |
           |   (Status: Ready, IP: SourceNode)      |                                        |
           |                                        |      [5] Pod Scheduled / Started       |
           |                                        |      (New Shim starts on Dest)         |
           |                                        |----------------------------------[Shim]|
           |                                        |                                        |
           |                                        |      [6] Find Matching Migration       |
           |                                        |<---------------------------------[Mgr] |
           |                                        |                                        |
           |                                        |      [7] Connect to Source (P2P)       |
           |<---------------------------------------+----------------------------------[Mgr] |
           |      (gRPC PullImage)                  |                                        |
           |--------------------------------------->|      (Stream Checkpoint Data)          |
           |                                        |                                        |
           |                                        |      [8] Restore Container             |
           |                                        |      (CRIU Restore from Local Data)    |
           |                                        |----------------------------------[Shim]|
           |                                        |                                        |
           |                                        |      [9] Update Migration CRD          |
           |                                        |<---------------------------------[Mgr] |
           |                                        |   (Status: Completed)                  |
```

**Step-by-Step Explanation:**
1.  **Initiation**: An evacuation is triggered (e.g., node drain). The Source Shim requests evacuation from the Source Manager.
2.  **Coordination**: The Source Manager creates a `Migration` Custom Resource. This CR acts as a handshake document, containing the source IP and port.
3.  **Checkpoint**: The Source Shim checkpoints the container. The data (memory pages, file descriptors) is stored locally on the Source Node's disk in a temporary location.
4.  **Advertisement**: The Source Manager updates the `Migration` CR to indicate it is "Ready" and provides connection details (IP/Port) for the image server.
5.  **Scheduling**: Kubernetes schedules the Pod to the Destination Node (standard K8s behavior). A new Zeropod Shim starts.
6.  **Discovery**: The Destination Shim asks the Destination Manager to restore. The Destination Manager queries the K8s API for a `Migration` CR matching the Pod.
7.  **Data Transfer (P2P)**: The Destination Manager connects **directly** to the Source Manager via gRPC (using Mutual TLS). It requests the checkpoint data (`PullImage`). The data is streamed directly from Source -> Destination, bypassing the API server or central storage.
8.  **Restore**: Once the data is fully transferred to the Destination Node, the Destination Shim invokes `runc restore` to resume the process.
9.  **Completion**: The `Migration` CR is updated to "Completed". The source data can now be cleaned up.

**Lazy Migration (Optional):**
If configured, "Lazy Pages" allows the process to start immediately on the Destination Node while memory pages are still being copied.
-   CRIU starts a user-fault-fd daemon on the Destination.
-   If the process accesses a memory page not yet present, the daemon fetches it on-demand from the Source.
-   This significantly reduces the "freeze time" during migration.

## Key Files & Interfaces

-   **`shim/container.go`**: The "Brain". Manages the state machine (Running <-> Scaled Down). Holds the `Activator` instance.
-   **`activator/activator.go`**: The "Nervous System". Listens for traffic, manages `bpf` maps, and triggers the restore hook.
-   **`manager/node/service.go`**: The "Coordinator". Runs as a DaemonSet. Exposes an RPC API for Shims to register/update status. Handles global node concerns like loading the initial BPF programs and managing migration data transfer.
-   **`activator/bpf.go`**: Handles the low-level interactions with eBPF maps (`active_connections`, `ingress_redirects`).

### 4. Migration Coordinator (CRD)

The `Migration` Custom Resource Definition (CRD) is the control plane storage for the migration process.

-   **Code Location**: [`api/runtime/v1/types.go`](../../api/runtime/v1/types.go)
-   **Purpose**:
    1.  **Service Discovery**: Allows the Destination Node to find the Source Node's temporary IP/Port for data transfer without a central registry.
    2.  **State Coordination**: Acts as a state machine (Pending -> Ready -> Completed) that both nodes watch.
    3.  **K8s Native**: Uses standard Kubernetes mechanisms (etcd, Watch API) avoiding the need for a separate database or consensus system.

**Key Fields:**
-   **`spec.sourceNode`**: The node name where the pod is currently running.
-   **`spec.restoreReady`**: Boolean flag set by the Source Manager when the checkpoint is complete and it is ready to serve data.
-   **`spec.containers[].imageServer`**: Struct containing `host` and `port` where the Destination Manager can connect to pull the checkpoint image (via gRPC).
