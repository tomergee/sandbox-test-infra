tftest
======

`tftest` is a tiny mimic of [kubetest](https://github.com/kubernetes/test-infra/tree/master/kubetest) which is designed to provision and tear down GKE clusters using Terraform.

Local development
-----------------

`tftest` binary
---------------

To test some changes to `tftest` binary itself, open a CL with the change, then select a job config that uses `tftest` and follow http://go/gke-scalability/custom-branches#how-to-get-a-base-ref to see how to leverage a CL in a manually kicked off Prow job.

Terraform scenarios
-------------------

### Prerequisites

If you do not have a fresh `terraform` binary on your workstation, then run the following commands:

```sh
gsutil cp gs://gke-scalability-binaries/terraform .
chmod a+x terraform
```

and then move the binary to one of the directories mentioned in the contents of you `PATH` env var.

### Validating Terraform configs

`cd` to the directory that contains `.tf` files and run:

```sh
terraform init
```

This will make the initial dependency selections that will initialize the dependency lock file. It should only be necessary once.

In the same directory, run:

```sh
terraform plan
```

This will read the current state of already existing GCP resources, compare it with the state defined in `.tf` files and print the diff that running `terraform apply` would introduce.

### Applying Terraform configs

You may need to reauthenticate to apply or unapply some configs:

```sh
gcloud auth application-default login
```

To apply config, run:

```sh
terraform apply --auto-approve --parallelism 20
```

The `--parallelism` argument specifies how many node pools can be created in parallel at max.

Drop the `--auto-approve` flag if you want to see the eventual diff in resources with a yes/no prompt.

### Unapplying Terraform configs (destroying created resources)

```sh
terraform destroy --auto-approve --parallelism 20
```

The `--parallelism` argument specifies how many node pools can be deleted in parallel at max.

Drop the `--auto-approve` flag if you want to see the eventual diff in resources with a yes/no prompt.

### Templating Terraform Configurations with tftest

Terraform configurations (`.tf` files) often require variable substitution for testing and flexibility. The `tftest` tool provides several methods for substituting variables within these files:

#### Substitution Methods

| Variable used in `.tf` file          | How to substitute                                | Notes                                                              |
|--------------------------------------|--------------------------------------------------|--------------------------------------------------------------------|
| `%TFTEST_PROJECT_NAME%`              | Automatically set by `tftest`                    | Uses the GCP project specified via a flag or retrieved from Boskos |
| `%TFTEST_CLUSTER_NAME%`              | Pass `--cluster` flag to `tftest`                | Uses the cluster name specified via the commandline flag           |
| `%TFTEST_NODE_POOL_RESOURCE_NAME%`   | Pass `--node-pool-name` flag to `tftest`         |                                                                    |
| `%TFTEST_MIN_MASTER_VERSION%`        | Calculated from the `--extract` flag to `tftest` |                                                                    |
| Variables matching `%(TFTEST_\w+?)%` | Set environment variable for `tftest` invocation | e.g., `export TFTEST_MACHINE_TYPE=n1-standard-1`                   |

#### Example Usage

```bash
# Set environment variables
export TFTEST_REGION=us-east1
export TFTEST_MACHINE_TYPE=n1-standard-1

# Run tftest with flags
tftest --node-pool-name node-pool --cluster test-cluster --boskos-pool=gke-sclability-100-project ...<other flags>...
```
