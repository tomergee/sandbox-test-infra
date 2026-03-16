Kueue Scale and Performance Testing Documentation
=================================================

Introduction to Kueue Scale Testing
-----------------------------------

Kueue, a job queueing controller for Kubernetes, must perform efficiently and reliably under various load conditions and at different cluster scales. The primary goals of Kueue scale and performance testing are:

-	**Performance Validation**: Ensure Kueue meets defined performance targets for job scheduling throughput and latency.
-	**Stability Assessment**: Verify Kueue's stability and resilience when managing a large number of workloads and resources.
-	**Bottleneck Identification**: Proactively identify and address performance bottlenecks in Kueue or its interactions with the Kubernetes API server.
-	**Feature Scalability**: Confirm that new and existing Kueue features (e.g., fair sharing, preemption, topology-aware scheduling) scale effectively.

To achieve these goals, we employ a comprehensive testing strategy primarily using **ClusterLoader2 (CL2)**, a Kubernetes-native load testing framework. Tests are executed regularly in a Continuous Integration (CI) environment managed by Prow.

Test Environment
----------------

Our testing infrastructure is designed to simulate real-world scenarios across various cluster sizes and configurations.

### CI Test Grid & Cluster Setup

Automated tests run on a regular schedule within our CI grid, orchestrated by Prow. These tests execute against GKE clusters of varying sizes:

-	100-node clusters
-	5,000-node clusters
-	20,000-node clusters
-	65,000-node clusters

The specific Prow jobs, their schedules, and unique configurations are detailed in the "Scheduled CI Jobs" section. Historical runs of the tests can be seen in https://testgrid.corp.google.com/gke-scalability-kueue.

### Manual Prow Job Execution

For manual test execution using a Prow job, the recommended approach is to duplicate an existing CI test for Kueue that closely matches the desired scale, Kueue version, and other requirements. Then, modify the configuration as needed (typically the CL2 parameters). Then to run a test, you need first to add you ldap to the end of the test name. Then run it using:

```sh
cd prow/gke-scalability-prow/config/gke
./execute-prow-job.old.sh TEST_NAME-{ldap}
# example
# ./execute-prow-job.old.sh ci-kubernetes-e2e-gke-rapid-latest-kueue-latest-100-cluster-full-{ldap}
```

### Local Run Setup

Local runs are useful for development, debugging, and iterative testing of Kueue configurations. Local run means that we are executing a local ClusterLoader2 scenario against an existing cluster (configured and accessible via kubectl, and cluster created either manually or via an earlier prowjob). To enable local execution, set the `CL2_LOCAL_RUN=true` environment variable. This parameter primarily adjusts absolute paths for certain scripts, allowing them to run from a local clone of the `perf-tests` repository (where ClusterLoader2 resides).

```bash
export CL2_LOCAL_RUN=true
# Other necessary exports for CL2 variables
cd perf-tests/clusterloader2
go run cmd/clusterloader.go \
    --testconfig="../testing/megacluster-kueue/config.yaml" \
    --provider=gke \
    --kubeconfig="${HOME}/.kube/config" \
    --v=2 \
    --report-dir ../../kueue_scale_test/
```

Key Testing Dimensions
----------------------

To ensure comprehensive coverage, Kueue is tested along several key dimensions:

### Testing Across Multiple Scales

As mentioned, Kueue's performance is validated on clusters ranging from 100 to 65,000 nodes. This multi-scale approach helps identify how Kueue's behavior and resource consumption change with cluster size and workload volume, revealing potential scaling limits or performance degradation at larger scales.

A key parameter for adjusting the test load proportionally to the cluster size is `CL2_MULTIPLIER`. This integer acts as a scaling factor for the number of jobs, job replicas, or pod counts within workloads, and resource quotas in `ClusterQueue`s. The total number of pods submitted in some test phases can be up to `10 * CL2_MULTIPLIER`. The value of `CL2_MULTIPLIER` is tailored for each specific scale test:

-	For 100-node tests (e.g., `kueue-100` scenario), `CL2_MULTIPLIER` is typically "9" (to test against ~90 worker nodes within a 100-node cluster).
-	For 5,000-node tests (e.g., `kueue-5k` scenario), `CL2_MULTIPLIER` is "490" (targeting ~4,900 nodes).
-	For 20,000-node tests (e.g., `kueue-20k` scenario), `CL2_MULTIPLIER` is "2000".
-	For 65,000-node tests (e.g., `kueue-65k` scenario), `CL2_MULTIPLIER` is "6500".

### Testing Against Multiple Kueue Versions

We test against various Kueue versions to ensure backward compatibility and detect regressions:

-	**`main`**: The latest development branch, incorporating latest changes.
-	**`latest`**: The most recent stable release.
-	**Specific tagged versions**: Such as `v0.11`, `v0.10`, to verify older supported releases.

The Kueue version for a test run is controlled by the `CL2_KUEUE_VERSION` environment variable. Note that older Kueue versions might not support all features present in newer ones. For example:

-	**Kueue v0.10**: Tests for this version disable LeaderWorkerSet (LWS) scenarios (`CL2_TAS_HERO_LWS_SCENARIO: false`) as full LWS integration was not available. Topology Aware Scheduling (TAS) behavior also differed; for instance, workloads on a TAS-enabled ClusterQueue might not have had a topology assigned by default if not explicitly annotated (`CL2_SKIP_NON_TAS_WORKLOADS_ON_TAS_CQ: true`).

### Workload Payload Size (TAS only)

The size of individual Pods within workloads can significantly impact API server and etcd performance, especially when creating or listing many objects. This is controlled by parameters like `CL2_TAS_POD_PAYLOAD_SIZE`, which adds an environment variable of a specified byte size to Pods, primarily in TAS tests.

The `common_run_workloads` module can also report the actual byte size of created Kubernetes objects (Jobs, Pods, etc.) to quantify this impact.

### Topology Configuration for TAS

The structure of the cluster topology plays a vital role in TAS performance and correctness. Our tests explore various topology configurations. If the test relies on GKE-provided labels (via compact placement), no further action is needed. Otherwise, custom TAS topologies can be simulated using the following approaches:

-	**Flexible Level 0**: The top level of a custom topology hierarchy (Level 0) can have an unlimited number of nodes. This to enable simulating large network groupings and ensures all nodes have a label.
-	**Lowest Level 1-to-1 Host Mapping**: Test configurations aim for the lowest (most granular) level of the custom topology to map directly to individual nodes. However, since `kubernetes.io/hostname` is needed for some TAS-related functions, the lowest level is omitted from the topology levels to avoid duplicate levels, while retaining the label on the node for neighbor tracking.
-	**Randomized Child Counts**: When generating custom topologies using `phase4/generate_topology_labels.sh`, the `CL2_CustomTopologyLevelChildrenRanges` parameter defines a `min:max` range for the number of children a parent node at each level can have. If `min` is not equal to `max`, the actual number of children for each parent is chosen *randomly* within this range. This introduces variability and helps create more realistic and diverse topology structures for testing, rather than uniform, predictable fan-outs.

### Ensuring 1-to-1 Pod-Node Mapping

Achieving a one-to-one mapping between Pods and Nodes is critical for certain test scenarios, particularly when evaluating node-level resource utilization or testing specific placement constraints. This is typically accomplished using a combination of `hostPort` and resource requests:

-	**Using `hostPort` (Non-TAS Scenarios)**:

	-	For general workloads not subject to Topology Aware Scheduling (TAS), setting a unique `hostPort` for each Pod effectively ensures that only one such Pod can run per Node.
	-	This is often controlled via a flag like `CL2_BIND_PORT=true` in test configurations (see the `KueueCommon` scenario in `kueue.go`), which instructs the workload generation logic to assign unique host ports.
	-	This method relies on the kube-scheduler's default behavior of preventing port collisions on a Node.

-	**Using Memory Requests (TAS Scenarios)**:

	-	Topology Aware Scheduling (TAS) in Kueue currently does not consider `hostPort` for scheduling decisions.
	-	To enforce a 1-to-1 Pod-Node mapping in TAS tests (Phase 4), a common strategy is to set the `CL2_MEMORY_REQUEST` for Pods to a value approximating the allocatable memory of a single Node (e.g., "1800" for 1800Mi, assuming nodes have slightly more available after system overhead and daemonsets).
	-	By requesting nearly enough of a Node's memory, each Pod effectively consumes an entire Node from Kueue's perspective for TAS. This prevents other Pods (with similar large memory requests) from being scheduled onto the same Node by Kueue, which is particularly relevant when testing TAS with `podSet-required-topology` where precise placement is key.

Test Scenarios: The `megacluster-kueue` Suite
---------------------------------------------

The core of our scale testing is the `megacluster-kueue` ClusterLoader2 (CL2) test suite. This suite comprises scenarios designed to evaluate Kueue's performance, scalability, and features under diverse conditions. Kubernetes resource definitions (e.g., `Job`, `Deployment`, `ClusterQueue`, `LocalQueue`, `ResourceFlavor`, `Topology`) are templatized using Go templates in the `common/` directory and dynamically populated based on test parameters.

The suite typically runs in multiple phases, each targeting specific Kueue functionalities:

### Phase 1: Burst Workloads

-	**Goal**: Assess Kueue's performance and stability when handling sudden, large influxes of job submissions.
-	**Workloads Used**: Kubernetes `Job` objects.
-	**Key Kueue CRDs**: `ClusterQueue`, `LocalQueue`.
-	**High-Level Steps**:
	1.	**Setup**: Create a namespace, a `ClusterQueue` (with resource quotas scaled by parameters like `CL2_MULTIPLIER`), and a `LocalQueue` pointing to it.
	2.	**Workload Submission**: Submit batches of `Job` objects of varying sizes (small, medium, large, size indicate number of jobs, not the size of the job).
	3.	**Measurement**: For each batch, measure scheduling throughput and pod startup latency.
	4.	**Verification**: Implicitly verified by `WaitForRunningPods`/`WaitForFinishedJobs`, `PodStartupLatency`, and `SchedulingThroughput`; diagnostic scripts count resources as well.
	5.	**Cleanup**: Delete all created workloads and Kueue resources.

### Phase 2: Priority and Preemption

-	**Goal**: Evaluate Kueue's ability to correctly prioritize workloads and preempt lower-priority ones when resources are scarce, and measure Kueue performance under these conditions.
-	**Workloads Used**:
	-	Many low-priority batch `Job`s of various sizes.
	-	Few medium-priority training `Job`s.
	-	A single high-priority inference workload (either `Deployment` or `LeaderWorkerSet`, controlled by `CL2_USE_DEPLOYMENT_FOR_INFERENCE`).
-	**Key Kueue CRDs**: `WorkloadPriorityClass`, `ClusterQueue` (with preemption enabled), `LocalQueue`.
-	**High-Level Steps**:
	1.	**Setup**: Create a namespace, `WorkloadPriorityClass` CRs (low, medium, high priorities), a `ClusterQueue` configured for preemption, and `LocalQueue`s.
	2.	**Saturate with Low-Priority Workloads**: Submit enough low-priority batch `Job`s to significantly utilize or saturate the `ClusterQueue`.
	3.	**Introduce Medium-Priority Workloads**: Submit medium-priority training `Job`s, which should preempt some batch workloads.
	4.	**Induce Preemption with High-Priority Workload**: Submit and scale up the high-priority inference workload. Observe Kueue preempting low and medium-priority workloads to admit the high-priority ones.
	5.	**Observe Recovery**: Scale down the high-priority workload and verify that previously preempted workloads are unsuspended and resume execution.
	6.	**Cleanup**: Delete all workloads and Kueue resources.

### Phase 3: Fair Sharing

-	**Goal**: Test Kueue's fair sharing mechanism, ensuring equitable resource distribution among competing `ClusterQueue`s within a cohort.
-	**Workloads Used**: Kubernetes `Job` objects.
-	**Key Kueue CRDs**: `WorkloadPriorityClass`, `ClusterQueue` (configured with `cohort` and `fairSharing.weight`), `LocalQueue`.
-	**High-Level Steps**:
	1.	**Setup**: Create namespaces for different "teams" (e.g., Team Alpha, Team Beta) and `WorkloadPriorityClass` CRs.
	2.	**Part 1 (Many medium jobs, Weight-Based Sharing, without Nominal Quota)**:
		-	Create `ClusterQueue`s within the same cohort: two for the teams (e.g., `fairsharing-alpha-cq`, `fairsharing-beta-cq`) with different `fairSharing.weight` values and zero initial `nominalQuota`. A third "buffer" `ClusterQueue` holds all the cohort's nominal quota.
		-	Submit jobs from Team Alpha. Then, submit high-priority jobs from Team Beta.
		-	**Verification**: Observe if Team Beta's jobs are admitted according to its fair share weight, preempting some of Team Alpha's jobs as Alpha borrowed resources.
	3.	**Part 2 (Few large jobs, with Nominal Quota)**:
		-	Update the team `ClusterQueue`s with non-zero `nominalQuota`. Adjust the buffer CQ accordingly.
		-	Submit jobs from Team Alpha to utilize its nominal quota and potentially borrow from the cohort.
		-	Submit jobs from Team Beta.
		-	**Verification**: Observe if Team Beta's jobs can preempt Team Alpha's *borrowed* resources to reclaim Beta's own nominal quota or its fair share of shared resources.
	4.	**Cleanup**: Delete all workloads and Kueue resources.

### Phase 4: Topology Aware Scheduling (TAS)

-	**Goal**: Verify Kueue's capability to schedule pods considering node topology, respecting `podset-preferred-topology` and `podSet-required-topology` annotations on `Workload` CRs.
-	**Workloads Used**: Primarily Kubernetes `Job` objects. For more complex scenarios, `LeaderWorkerSet` (LWS) and `JobSet` are used.
-	**Key Kueue CRDs**: `Topology`, `ResourceFlavor` (associating with a `Topology`), TAS-enabled `ClusterQueue`, `LocalQueue`. LWS and JobSet CRDs are also relevant.

The Phase 4 TAS tests are structured in multiple layers, leveraging various ClusterLoader2 modules:

1.	**Topology Definition (configured by `phase4_tas` module)**: This initial layer defines the cluster topology used for testing.

	-	Tests can utilize standard GKE topology labels (e.g., `cloud.google.com/gce-topology-block`) controlled by the `CL2_DefaultGkeTopology` parameter.
	-	Alternatively, custom hierarchical topologies can be built. The `phase4/generate_topology_labels.sh` script labels cluster nodes with custom labels (e.g., `my-custom-topo/level0=L0-1`), and Kueue `Topology` CRs are then created to formally define these relationships. Parameters like `CL2_CustomTopologies`, `CL2_CustomTopologyLevels`, and `CL2_CustomTopologyLevelChildrenRanges` control the generation of these custom topologies.

2.	**Scenario Execution (defined within `single_topology_e2e_test` module)**: Within each defined topology, various scenarios are executed to test different aspects of TAS. These scenarios are enabled or disabled via specific `CL2_` environment variables:

	-	**Hero Job Scenario (`CL2_TAS_HERO_JOB_SCENARIO=true`\)**: Focuses on a single, large `Job` with topology preferences or requirements.
	-	**Multiple Jobs Scenario (`CL2_TAS_MULTIPLE_JOBS_SCENARIO=true`\)**: Tests concurrent `Job`s, each with its own topology preferences or requirements.
	-	**Hero JobSet Scenario (`CL2_TAS_HERO_JOBSET_SCENARIO=true`\)**: Uses a large `JobSet` to test scheduling of tightly coupled jobs with inter-dependencies and potentially complex, multi-role topology constraints. The integration scope for JobSet with Kueue can be controlled via `CL2_TAS_JOBSET_INTEGRATION_SCOPE` (e.g., "jobset" or "replicatedjob").
	-	**Hero LWS Scenario (`CL2_TAS_HERO_LWS_SCENARIO=true`\)**: Similar to JobSet, employs a `LeaderWorkerSet`. The integration scope for LWS with Kueue can be controlled via `CL2_TAS_LWS_INTEGRATION_SCOPE` (e.g., "lws" or "worker").

3.	**Workload Testing Steps (handled by `partial_run_topology_job` module)**: For each scenario, the `partial_run_topology_job` module executes multiple steps to test workload behavior under different conditions:

	-	**Setup**: Create namespace, Kueue `Topology` CR(s), `ResourceFlavor`(s) linked to these topologies, a TAS-enabled `ClusterQueue`, and `LocalQueue`(s).
	-	**Baseline Tests**:
		-	**No Kueue Baseline**: Submit `Job/JobSet/LWS` directly to Kubernetes to establish a non-Kueue performance baseline (i.e., scheduling using kube-scheduler only).
		-	**Kueue, No TAS Baseline**: Submit `Job/JobSet/LWS` to a default Kueue queue without TAS to compare performance.
	-	**TAS Queue Tests**:
		-	**No Annotations**: Submit `Job/JobSet/LWS` to the TAS-enabled queue without any explicit topology annotations on the `Workload`.
		-	**Preferred Topology**: Submit `Job/JobSet/LWS` whose `Workload` CRs have `kueue.x-k8s.io/podset-preferred-topology` annotations. Verification ensures pods are scheduled in the preferred domain if resources allow.
		-	**Required Topology**: Submit `Job/JobSet/LWS` whose `Workload` CRs have `kueue.x-k8s.io/podset-required-topology` annotations. Verification ensures pods are scheduled *only* in the required domain, or remain pending if not possible.

4.	**Workload Lifecycle Management (implemented by `common_run_workloads` module)**: At the lowest level, for each step within a scenario, the `common_run_workloads` module handles fundamental operations:

	-	**Creation**: Submitting the specified workloads to the cluster.
	-	**Scheduling and Running**: Monitoring and waiting for the workloads' pods to be scheduled and running by Kueue and Kubernetes.
	-	**Deletion**: Cleaning up created workloads after the test step is complete. This module also facilitates basic performance measurements like scheduling throughput and pod startup latency.

Deep Dive: Key Modules
----------------------

The `megacluster-kueue` test suite leverages several specialized and reusable ClusterLoader2 modules and scripts. This section provides a deeper look into some critical components.

### Setting up Cluster CRDs

The `setup_cluster.sh` script plays an important role in the setup process. Before each test run, this script:

1.	Downloads the manifests for the specified Kueue version (and optionally for integrated components like LeaderWorkerSet - LWS and JobSet).
2.	Applies necessary patches using a custom patcher script `kueue_patcher_script.sh` to customize the Kueue deployment. These patches can, for example, increase controller replicas, adjust API QPS limits, or enable/disable specific Kueue features for the test.
3.	Applies necessary patches for LWS and JobSet using diff files (`jobset.diff` and `lws.diff`).
4.	Applies the modified manifests to the cluster and waits until the pods are deployed and running.

### Topology Label Generation (`phase4/generate_topology_labels.sh`\)

This script is a utility for setting up custom cluster topologies required for Topology Aware Scheduling (TAS) tests (Phase 4). Its primary purpose is to dynamically label Kubernetes nodes with hierarchical custom topology labels, simulating diverse hardware layouts for Kueue testing.

-	**Functionality**:

	-	The script generates hierarchical labels (e.g., `my-custom-topo/level0=L0-1`, `my-custom-topo/level1=L0-1-L1-0`) and applies them to nodes in the test cluster using `kubectl label node`. It constructs these topologies based on configurable parameters:
	-	It defines a specified number of distinct custom topology hierarchies.
	-	For each hierarchy, it creates a defined number of levels.
	-	For levels beyond the root (Level 0), it determines the number of children for each parent node by either selecting a fixed number or randomly choosing within a specified `min:max` range. This allows for creating both uniform and varied, more realistic topology structures.
	-	The test suite (not this script) then creates Kueue `Topology` Custom Resources (CRs) to formally define these hierarchical relationships for Kueue's scheduler.

-	**Parameters**: The script's behavior is controlled by the following `CL2_` environment variables:

	-	**Topology Definition Parameters**: These directly influence the structure of the generated topologies.
		-	`CL2_CustomTopologies`: Number of distinct custom topology hierarchies to generate.
		-	`CL2_CustomTopologyLevels`: Depth of each custom topology hierarchy (e.g., 3 for `level0`, `level1`, `level2`).
		-	`CL2_CustomTopologyLevelChildrenRanges`: Defines the `min:max` fan-out range for children at each level beyond Level 0. For instance, `"64:64,16:16"` (used in `KueueTasSuperSlicing`) means level-0 parents will each have exactly 64 level-1 children, and each of those level-1 children will have exactly 16 level-2 children. A range like `"16:20,16:20,16:20"` would mean parents at each respective level have a random number of children between 16 and 20.
	-	**Script Control Parameters**: These affect how the script executes rather than the topology structure itself.
		-	`CL2_CustomTopologyDryRunLabelling`: If `true`, the script only prints the `kubectl label` commands without executing them, useful for debugging.
		-	`CL2_DefaultGkeTopology`: If `true`, the test uses standard GKE topology labels instead of generating custom ones, and this script is not run.
		-	`CL2_SKIP_GENERATING_TOPOLOGY_LABELS`: If `true`, this script is skipped entirely. This is used to avoid repeated labeling of the same cluster.

### Workload Management (`modules/common_run_workloads.yaml`\)

This versatile and highly reusable ClusterLoader2 module orchestrates the lifecycle of various Kubernetes workloads throughout the test phases. It abstracts the complexities of workload submission, monitoring, and basic performance measurement.

-	**Functionality**:
	-	**Workload Lifecycle Management**: Creates, submits, monitors, and optionally deletes batches of Kubernetes `Job`, `Deployment`, `LeaderWorkerSet`, or `JobSet` objects. It supports workloads of varying sizes and includes logic to wait for pods to reach `Running` state or for jobs to `Complete`.
	-	**Performance Measurement & Reporting**: Integrates with measurement components to record key metrics. It can:
		-	Collect scheduling throughput and pod startup latency.
		-	Report the byte size of created Kubernetes objects to analyze API server load (via `ReportWorkloadsSize`).
		-	Report Kueue controller resource metrics.
		-	Collect Go pprof profiles (CPU and heap) from the Kueue controller.
-	**Key Parameters**: Its behavior is influenced by several `CL2_` environment variables, often passed down from phase-specific modules:
	-	`CL2_MULTIPLIER`: Scales the number of replicas or pod counts within workloads.
	-	`CL2_CPU_REQUEST`, `CL2_MEMORY_REQUEST`: Define resource requests for pods created by workloads.
	-	`CL2_SLEEP_DURATION`: Controls pauses after workload submission or deletion.
	-	`CL2_TAS_POD_PAYLOAD_SIZE`: Increases the size of Pod objects, impacting API server performance.
	-	`CL2_THROUGHPUT_THRESHOLD`, `CL2_POD_STARTUP_LATENCY_THRESHOLD`: Define performance targets for the workloads it manages.

### Other Supporting Files and Modules

Beyond core topology generation and workload management, several other files and modules are important:

-	**Central Configuration (`config/megacluster-kueue/config.yaml`\)**: The main ClusterLoader2 configuration file orchestrating the entire test suite. It defines global parameters, includes test phases, and sets up the overall execution flow.
-	**Performance Measurement Modules (`modules/measurements.yaml`, `modules/scheduling-throughput.yaml`\)**: Responsible for integrating with Prometheus and other monitoring tools to collect and report key performance indicators (KPIs) like API responsiveness, API availability, and detailed scheduling throughput.
-	**Resource Definition Templates (`common/*.yaml`\)**: Contains Go templates for Kubernetes resources (e.g., `job.yaml`, `clusterqueue.yaml`, `localqueue.yaml`). These templates allow dynamic generation of Kubernetes objects with parameters specific to each test scenario.
-	**Diagnostic Scripts (`phaseX/check_count.sh`\)**: Located in phase-specific subdirectories (e.g., `phase1/check_count.sh`), these shell scripts verify the state of Kubernetes and Kueue resources during test runs (e.g., counting running/pending pods and jobs), aiding in real-time diagnostics and post-mortem analysis.
-	**PProf Profiling Module (`modules/pprof_measurement.yaml` and `modules/pprof.yaml`\)**: Facilitates the collection of Go pprof profiles (CPU and heap) from the leader pod of the Kueue controller manager. Its execution is controlled by the `ReportPprof` parameter within the `common_run_workloads.yaml` module.

Workloads and CRDs Under Test
-----------------------------

The scale tests interact with several types of Kubernetes workloads and CustomResourceDefinitions (CRDs).

### Types of Workloads Used

-	**`Job`**: The primary workload type for most performance, scalability, and basic feature tests (burst, preemption, fair sharing, simple TAS).
-	**`Deployment` / `LeaderWorkerSet` (LWS)**:
	-	Used for simulating inference-style, long-running, or high-priority workloads, particularly in preemption scenarios (Phase 2).
	-	LWS is used for TAS tests involving stateful applications or co-located components that need to be scheduled as a single, atomic unit with topology constraints (e.g., Hero LWS Scenario).
-	**`JobSet`**:
	-	Used in advanced TAS scenarios (e.g., Hero JobSet Scenario) to test scheduling of tightly coupled jobs with inter-dependencies and potentially complex, multi-role topology constraints.

### Key CRDs Involved

The tests utilize the following CRDs:

-	**Kueue CRDs**:
	-	`Workload`: Represents a unit of work to be scheduled by Kueue. Tests focus on creation rate, update frequency (status changes), and size.
	-	`ClusterQueue`: Defines a cluster-wide queue with resource quotas, cohort membership, and scheduling policies (preemption, fair sharing, TAS).
	-	`LocalQueue`: Namespaced queues that act as entry points for `Workload`s into `ClusterQueue`s.
	-	`ResourceFlavor`: Defines types of available resources (e.g., different GPU types) and can be associated with node topologies.
	-	`Topology`: Defines hierarchical node groupings for TAS.
	-	`WorkloadPriorityClass`: Defines priority levels for `Workload`s.
-	**Integrated Workload CRDs**:
	-	`LeaderWorkerSet` (alpha.jobset.x-k8s.io): For co-scheduling groups of pods, used with TAS and in the Phase 2 preemption scenario.
	-	`JobSet` (jobset.x-k8s.io): For managing sets of interdependent batch jobs, also used with TAS.

CRD Configurations for Large Scale
----------------------------------

To ensure Kueue and its integrated components perform reliably at large scales, their default manifests are often modified during test setup. These modifications aim to increase throughput, handle more concurrent operations, and provide better observability.

### Kueue Controller Manager & CRDs

Kueue manifests (downloaded based on `CL2_KUEUE_VERSION`) are patched by `kueue_patcher_script.sh`. Key changes include:

-	**Controller Replicas**: Increased via `CL2_KUEUE_CONFIGURATION_REPLICAS` for higher concurrency and fault tolerance.
-	**Resource Allocation**: CPU/memory requests and limits for the Kueue controller are adjusted via `CL2_KUEUE_CONFIGURATION_CPU` and `CL2_KUEUE_CONFIGURATION_MEMORY`.
-	**High Throughput Settings (`CL2_KUEUE_CONFIGURATION_HIGH_THROUGHPUT=true`\)**:
	-	**API Client QPS/Burst**: Kubernetes API client QPS (Queries Per Second) and burst limits for Kueue are significantly increased (e.g., QPS to 1000, Burst to 1000).
	-	**Controller Concurrency**: `groupKindConcurrency` for watched resources (Job, Pod, Workload, etc.) is increased (e.g., from 5 to 500), allowing parallel processing of more items.
-	**PProf Endpoint**: Enabled by setting `pprofBindAddress` (e.g., to `:8083`) for performance profiling.
-	**Probe Adjustments**: Liveness and readiness probe `initialDelaySeconds` and `periodSeconds` are increased for better tolerance under high load.
-	**Feature Gates & Integrations**:
	-	`TopologyAwareScheduling` feature gate is managed by `CL2_KUEUE_CONFIGURATIONS_TAS_ENABLED`.
	-	Integrations with `Deployment` and `LeaderWorkerSet` (and fair sharing) are typically disabled if `CL2_KUEUE_CONFIGURATIONS_REDUCED=true`.
-	**Job Management Scope**: `managedJobsNamespaceSelector` is set to `matchLabels: {kueue-managed: "true"}`.

### LeaderWorkerSet (LWS) CRDs

If LWS is part of the test (i.e., `CL2_KUEUE_CONFIGURATIONS_REDUCED=false`), its official manifests are downloaded.

-	An optional `lws.diff` patch can be applied by `setup_cluster.sh` to customize LWS controller settings for scale.

### JobSet CRDs

If JobSet is included (via `CL2_INSTALL_JOBSET=true`), its official manifests are downloaded.

-	An optional `jobset.diff` patch can be applied by `setup_cluster.sh` for custom scale-testing adjustments.

These patches generally aim to improve resource limits, concurrency, or other performance-related settings for LWS and JobSet controllers.

Measurements, Profiling, and Reporting
--------------------------------------

A variety of metrics are collected to evaluate Kueue's performance and identify issues.

### Key Performance Indicators (KPIs)

-	**End-to-End (E2E) Latency**: Measures key timing aspects of workload lifecycle, such as the time taken for a workload’s Pods to transition from creation to running state, or for an entire Job to complete. The tests also monitor the in-progress status of workloads by tracking counts of Pods in various states (e.g., created, running, pending, terminated).
-	**Pod Startup Latency**: The time from Pod creation to it being marked as running.
-	**Scheduling Throughput**: The rate at which Pods are successfully assigned to Nodes.
-	**Workload Object Size**: The byte size of created Kubernetes objects (Kueue `Workload`s, `Job`s, `Pod`s), measured by serializing to YAML/JSON. This helps understand the load on the API server and etcd, especially with many or large objects (e.g., pods with large payloads via `CL2_TAS_POD_PAYLOAD_SIZE`).
-	**Resource Usage Reporting**: Total memory and CPU usage of Kueue components are monitored using `kubectl top pods`.

-	**PProf Profiles**: Performance profiling is important for diagnosing bottlenecks within Kueue components. CPU and Memory (Heap) profiles are collected from the Kueue controller manager's pprof endpoints (e.g., on port `8083`). A utility pod (`modules/pprof.yaml`) is used to access these profiles. Profiles are captured during workload creation and after pods are running, currently in TAS phase, when `ReportPprof` is enabled in `common_run_workloads.yaml`.

### Results Dashboarding

All test results, including KPIs and profiling data, are typically uploaded to **Perf-Dash** for visualization, historical tracking, and regression analysis.

Key Configuration Parameters
----------------------------

The test suite's behavior is extensively controlled by environment variables, usually set in Prow job definitions.

### Terraform/Cluster Configurations

-	`TFTEST_HEAPSTER_NODE_COUNT`, `TFTEST_HEAPSTER_NODE_POOL_MACHINE`: Configure resources for Heapster nodes.
-	`TFTEST_NODE_POOL_COUNT`, `TFTEST_NODE_POOL_COUNT_COMPACT`, `TFTEST_NODE_POOL_SIZE`, `TFTEST_NODE_POOL_SIZE_COMPACT`, `TFTEST_INITIAL_NODE_COUNT`: Configure resources for worker nodes (both normal and compact placement).
-	`TFTEST_NODE_LOCATIONS`: List of locations (zones) for nodes.
-	`TFTEST_MAX_PODS_PER_NODE`: Maximum number of pods allowed per node.
-	`TFTEST_NETWORK`: Name of the network used by the cluster.

### Test Execution Control

-	`CL2_ENABLE_PHASE_1`, `CL2_ENABLE_PHASE_2`, `CL2_ENABLE_PHASE_3`, `CL2_ENABLE_PHASE_4`: Booleans to enable/disable respective test phases.
-	`CL2_LOCAL_RUN`: If `true`, allows for local running with locally cloned perf-tests repository (the cluster can be created via a prowjob though).
-	`CL2_SLEEP_ONLY`: If `true`, sets up Kueue and sleeps, skipping all phases. Used for local testing against a large cluster where Prow handles cluster creation, and custom CL2 tests are run locally.
-	`CL2_SLEEP_DURATION_BETWEEN_PHASES`: Pause duration between major test phases.
-	`CL2_SLEEP_DURATION`: Default sleep duration after creating/deleting workloads within a phase.

### Kueue CRD Configuration

-	`CL2_KUEUE_VERSION`: Specifies the Kueue version to test (e.g., "main", "latest", "v0.10.0").
-	`CL2_KUEUE_CONFIGURATIONS_REDUCED`: Boolean. If `true`, disables Deployment/LWS integration and fair sharing, and skips LWS installation.
-	`CL2_KUEUE_CONFIGURATIONS_TAS_ENABLED`: Boolean. If `true` (default), enables the `TopologyAwareScheduling` feature gate in Kueue.
-	`CL2_ENABLE_TAS_KUEUE_CONTROLLER_RESOURCES`: Boolean. If `true`, enable resource monitoring of Kueue controller manager during TAS phase.
-	`CL2_KUEUE_CONFIGURATION_CPU`, `CL2_KUEUE_CONFIGURATION_MEMORY`, `CL2_KUEUE_CONFIGURATION_REPLICAS`: Define CPU, memory, and replica count for the Kueue controller.
-	`CL2_KUEUE_CONFIGURATION_HIGH_THROUGHPUT`: Boolean. If `true`, configures the Kueue controller for high QPS and concurrency.

### Scaling and Resource Allocation

-	`CL2_MULTIPLIER`: Integer scaling factor for job replicas, pod counts, and `ClusterQueue` quotas. The total number of pods can be up to `10 * CL2_MULTIPLIER` (e.g., for a 20K node scale test, `CL2_MULTIPLIER` is 2000). It's recommended that the multiplier value be a multiple of 10, as some phases assume this, unless multiplier is less than 10.
-	`CL2_CPU_REQUEST`: Base CPU request for individual pods (e.g., "0.3").
-	`CL2_MEMORY_REQUEST`: Base memory request for pods (e.g., "1800" for 1800Mi). In Phase 4 (TAS), this is used to ensure 1-to-1 node-pod mapping, as `hostPort` is not compatible with TAS.

### Kueue and Workload Configurations

-	`CL2_SCHEDULER_NAME`: Kubernetes scheduler name to use for test pods (e.g., `default-scheduler`, `gke.io/first-fit`).
-	`CL2_NAMESPACE*`: Defines namespace names for different test phases/teams.
-	`CL2_BIND_PORT`: Boolean. When `true`, assigns a unique `hostPort` to pods in non-TAS scenarios to ensure a 1-to-1 pod-to-node mapping. This is distinct from Kueue controller's pprof/metrics port, which is configured via `pprofBindAddress`.
-	`CL2_ENABLE_TAS_KUEUE_PPROF`: Boolean. Enables pprof measurements for the Kueue controller during TAS phase.
-	`CL2_USE_DEPLOYMENT_FOR_INFERENCE`: Boolean for Phase 2. If `true`, the high-priority inference workload is a `Deployment`; otherwise, it's a `LeaderWorkerSet`.
-	`CL2_FAIR_SHARING_WEIGHT_ALPHA`, `CL2_FAIR_SHARING_WEIGHT_BETA`: Integer weights for `ClusterQueue` fair sharing in Phase 3.
-	`CL2_InitialCQQuota`: Initial `nominalQuota` for team CQs in Phase 3, Part 2.

#### Topology Aware Scheduling (TAS) Specifics

-	`CL2_DefaultGkeTopology`: Boolean. If `true`, uses standard GKE topology labels.
-	`CL2_SKIP_GENERATING_TOPOLOGY_LABELS`: Boolean. If `false` (and `CL2_DefaultGkeTopology` is `false`), `phase4/generate_topology_labels.sh` is run.
-	`CL2_CustomTopologies`: Integer, number of custom topology hierarchies to create.
-	`CL2_CustomTopologyLevels`: Integer, number of levels in each custom topology.
-	`CL2_CustomTopologyLevelChildrenRanges`: String defining min:max children per parent at each level (e.g., `"1:3,2:5"`).
-	`CL2_CustomTopologyDryRunLabelling`: Boolean. If `true`, `generate_topology_labels.sh` runs in dry-run mode.
-	`CL2_TAS_POD_PAYLOAD_SIZE`: Size (in bytes) of an environment variable added to pods in TAS tests to increase Pod object size.
-	`CL2_TAS_SMALL_WORKLOAD_SIZE`: Defines the size (e.g., number of pods) of "small" workloads in TAS scenarios.
-	`CL2_TAS_HERO_JOB_SCENARIO`, `CL2_TAS_HERO_JOBSET_SCENARIO`, `CL2_TAS_HERO_LWS_SCENARIO`, `CL2_TAS_MULTIPLE_JOBS_SCENARIO`: Booleans to enable specific TAS hero/multi-job test scenarios.
-	`CL2_TAS_JOBSET_INTEGRATION_SCOPE`, `CL2_TAS_LWS_INTEGRATION_SCOPE`: Define integration scope for JobSet/LWS with TAS (e.g., "jobset", "replicatedjob", "lws", "worker").
-	`CL2_SKIP_NON_TAS_WORKLOADS_ON_TAS_CQ`: Boolean, relevant for older Kueue versions; skips workloads without TAS labels on TAS CQs.
-	`CL2_SKIP_REQUIRED_TOPOLOGY_WORKLOAD`: Boolean. If `true`, may skip submitting workloads with strict `podSet-required-topology`. Used in large-scale tests to avoid failures when scheduling with required topology is not possible.
-	`CL2_TARGET_TOPOLOGY_LEVEL`: Integer, specifies a topology level to target for preferred/required topology in TAS tests. Works with custom generated TAS topologies.

### Measurement Thresholds & Parameters

-	`CL2_DEFAULT_QPS`: Global QPS limit for ClusterLoader2's API interactions.
-	`CL2_THROUGHPUT_THRESHOLD`: Minimum acceptable pod scheduling throughput (pods/second). Override custom limits used across phase.
-	`CL2_POD_STARTUP_LATENCY_THRESHOLD`: Maximum acceptable pod startup latency (e.g., "10s"). Override custom limits used across phase.
-	`CL2_ALLOWED_SLOW_API_CALLS`: For the `APIResponsivenessPrometheus` check.
-	`CL2_API_AVAILABILITY_PERCENTAGE_THRESHOLD`: Minimum API server availability.
-	`CL2_CLUSTER_OOMS_IGNORED_PROCESSES`: String, list of process names to ignore for OOM detection.
-	`CL2_ENABLE_VIOLATIONS_FOR_API_CALL_PROMETHEUS_SIMPLE`: Boolean, enables a simplified Prometheus query for API call violations.

Scheduled CI Jobs
-----------------

The following Prow jobs run regularly to continuously validate Kueue's scalability and performance.

-	**100-node tests (Daily):**

	-	`ci-kubernetes-e2e-gke-rapid-latest-kueue-main-100-cluster-full`
		-	Cron: `0 2 * * *` (2 AM UTC)
		-	Kueue Version: `main` (`CL2_KUEUE_VERSION: "main"`\)
		-	Scheduler: `default-scheduler`
		-	Full feature set (`CL2_KUEUE_CONFIGURATIONS_REDUCED: false`), TAS enabled.
	-	`ci-kubernetes-e2e-gke-rapid-latest-kueue-latest-100-cluster-full`
		-	Cron: `0 4 * * *` (4 AM UTC)
		-	Kueue Version: `latest` (`CL2_KUEUE_VERSION: "latest"`\)
		-	Scheduler: `default-scheduler`
		-	Full feature set, TAS enabled.
	-	`ci-kubernetes-e2e-gke-rapid-latest-kueue-v0.11-100-cluster-full`
		-	Cron: `0 6 * * *` (6 AM UTC)
		-	Kueue Version: `v0.11` (`CL2_KUEUE_VERSION: "v0.11"`\)
		-	Scheduler: `default-scheduler`
		-	Full feature set, TAS enabled.
	-	`ci-kubernetes-e2e-gke-rapid-latest-kueue-v0.10-100-cluster-full`
		-	Cron: `0 8 * * *` (8 AM UTC)
		-	Kueue Version: `v0.10` (`CL2_KUEUE_VERSION: "v0.10"`\)
		-	Scheduler: `default-scheduler`
		-	Specific v0.10 configs: `CL2_SKIP_NON_TAS_WORKLOADS_ON_TAS_CQ: true`, `CL2_TAS_HERO_LWS_SCENARIO: false`. Full feature set otherwise.

-	**5,000-node tests (Twice a week):**

	-	`ci-kubernetes-e2e-gke-rapid-latest-5000-cluster-kueue-tas`
		-	Cron: `0 3 * * 0,4` (3 AM UTC on Sunday and Thursday)
		-	Kueue Version: `latest`
		-	Scheduler: `gke.io/first-fit`
		-	Focus: TAS (`CL2_ENABLE_PHASE_4: true`, other phases `false`). Reduced Kueue config (`CL2_KUEUE_CONFIGURATIONS_REDUCED: true`). High throughput Kueue settings (`CL2_KUEUE_CONFIGURATION_HIGH_THROUGHPUT=true`).

-	**20,000-node tests (Weekly):**

	-	`ci-kubernetes-e2e-gke-rapid-latest-20000-cluster-kueue-tas`
		-	Cron: `0 4 * * 4` (4 AM UTC on Thursday)
		-	Kueue Version: `latest`
		-	Scheduler: `gke.io/first-fit`
		-	Focus: TAS. Reduced Kueue config (`CL2_KUEUE_CONFIGURATIONS_REDUCED: true`). High throughput Kueue settings (`CL2_KUEUE_CONFIGURATION_HIGH_THROUGHPUT=true`).
	-	`ci-kubernetes-e2e-gke-rapid-latest-20000-cluster-kueue-ssi` (SSI requirements)
		-	Cron: `0 4 * * 3` (4 AM UTC on Wednesday)
		-	Kueue Version: `latest`
		-	Scheduler: `gke.io/first-fit`
		-	Focus: LWS and JobSet with TAS (`CL2_TAS_HERO_LWS_SCENARIO: true`, `CL2_TAS_HERO_JOBSET_SCENARIO: true`). Different topology configuration (`CL2_TARGET_TOPOLOGY_LEVEL: 1`). Full Kueue config (`CL2_KUEUE_CONFIGURATIONS_REDUCED: false`). High throughput Kueue settings (`CL2_KUEUE_CONFIGURATION_HIGH_THROUGHPUT=true`).

-	**65,000-node tests (Weekly):**

	-	`ci-kubernetes-e2e-gke-rapid-latest-65000-cluster-kueue-performance`
		-	Cron: `0 3 * * 6` (3 AM UTC on Saturday)
		-	Kueue Version: `latest`
		-	Scheduler: `gke.io/first-fit`
		-	Focus: General performance (Phases 1, 2, 3 enabled; Phase 4/TAS disabled). Full Kueue config without TAS (`CL2_KUEUE_CONFIGURATIONS_REDUCED: false`, `CL2_KUEUE_CONFIGURATIONS_TAS_ENABLED: false`). High throughput Kueue settings. Uses `Deployment` for Phase 2 (priority and preemption) by default (`CL2_USE_DEPLOYMENT_FOR_INFERENCE=true`).

All jobs use `perfDashJobType: kueue` for results dashboarding, with `perfDashPrefix` varying per job.

Building a Custom Test Using Kueue Scenarios and Config-Gen
-----------------------------------------------------------

The `config-gen` tool and Kueue scenarios provide a flexible way to build custom tests.

### Understanding Kueue Scenarios (`kueue.go`\)

In `test-infra/prow/gke-scalability-prow/config_generator/pkg/scenario/kueue.go`, various scenarios are defined as Go functions. Each scenario encapsulates a specific combination of flags and configurations relevant to a particular Kueue feature or testing goal.

Examples:

-	`KueueCommon`: Defines common settings like resources, labels, and default argument environments.
-	`KueuePerformance`: Enables performance-focused phases (1, 2, and 3) and disables TAS.
-	`KueueTas`: Configures settings specifically for Topology Aware Scheduling (TAS) tests.

### Composing Scenarios

The `config-gen` tool processes a YAML definition (e.g., in `config-gen/batch/gke-scalability-megacluster-kueue.yaml`) that lists a sequence of scenarios. Each scenario in the list is applied in order, potentially modifying or overriding configurations set by previous ones.

For instance, a test definition might include:

```yaml
periodics:
  - name: ci-kubernetes-e2e-gke-rapid-latest-kueue-main-100-cluster-full
    scenarios:
    - base
    - kueue-common # Sets many CL2_KUEUE_* defaults
    - kueue-performance # Overrides CL2_ENABLE_PHASE_*, CL2_KUEUE_CONFIGURATIONS_REDUCED
    - kueue-tas # Overrides CL2_ENABLE_PHASE_4, CL2_KUEUE_CONFIGURATIONS_TAS_ENABLED
    - kueue-100 # Further overrides CL2_MULTIPLIER, CL2_KUEUE_CONFIGURATIONS_REDUCED, etc.
    config:
      envs:
        CL2_KUEUE_VERSION: "main" # Specific override for this job
```

In this example, `kueue-common` establishes baseline Kueue settings. Then, `kueue-performance` might enable specific performance-related test phases and set `CL2_KUEUE_CONFIGURATIONS_REDUCED` to `false`. Subsequently, `kueue-tas` could enable Phase 4 for TAS testing and set `CL2_KUEUE_CONFIGURATIONS_TAS_ENABLED` to `true`. Finally, the `kueue-100` scenario tailors settings for a 100-node cluster, potentially overriding `CL2_KUEUE_CONFIGURATIONS_REDUCED` back to `false` if LWS is needed for that scale. The `config` block at the job level provides the final layer of specific overrides, like setting `CL2_KUEUE_VERSION`.

To generate a new prowjob (to be used regularly as a CI job), compose one in `prow/gke-scalability-prow/config-gen/batch/gke-scalability-megacluster-kueue.yaml` and then generate it using the `generate_config.sh` script:

```sh
sh prow/gke-scalability-prow/generate_config.sh
```

The results will be reflected in the file `prow/gke-scalability-prow/config/batch/gke-scalability-megacluster-kueue.yaml`. Then you can run it using the following command (you need to add `-{ldap}` to the end of the test name):

```sh
cd prow/gke-scalability-prow/config/gke
./execute-prow-job.old.sh TEST_NAME-{ldap}
```

For more details about creating your own test, please follow: go/gke-scalability/creating-new-test.

Open Issues and Future Work
---------------------------

This section outlines ongoing areas of investigation and potential future enhancements for Kueue scale testing.

-	**Resource Allocation Optimization**: Fine-tuning resource configurations (CPU, memory, replicas via `CL2_KUEUE_CONFIGURATION_*` variables) for Kueue, LWS, and JobSet controllers, as well as Heapster pool sizing (`TFTEST_HEAPSTER_*` variables), is needed for cost-cutting while ensuring stability and performance across different scales.
-	**Scheduler Performance Analysis**: While 100-node tests use `default-scheduler` and larger scales use `gke.io/first-fit`, a more in-depth comparative analysis of scheduler performance characteristics across all scales could yield further insights.
-	**Performance Threshold Tightening**: Based on historical data from Perf-Dash, performance thresholds (e.g., `CL2_THROUGHPUT_THRESHOLD`, `CL2_POD_STARTUP_LATENCY_THRESHOLD`) should be periodically reviewed and tightened to ensure early detection of regressions and maintain high performance standards.
