# Automated setup script for Cluster Stacks on OpenStack

This script bootstraps Cluster Stacks on OpenStack, namely the SCS gx-scs environment.

Quick-start source: <https://github.com/SovereignCloudStack/cluster-stacks/blob/f971bbaf53aef6231c1c0825f611259528a7593f/README.md>

Run `create_all.sh` with bash or zsh and follow the displayed instructions.

## Pre-requirements

### CLI tools

As stated in the source README, you need the following CLI tools:

* `kind` (works with both Docker and Podman)
* `kubectl`
* `helm`
* `clusterctl`
* `jq`

Go with envsubst is not needed here because it is replaced with Python.


### Config files

* `gh-pat`: plain text file that contains your Github PAT
* `clouds.yaml`: credentials from your OpenStack project
* `cluster_def.yaml`: from the repo ("Create the workload cluster resource (SCS-User/customer)")
* `clusterstack_def.yaml`: from the repo ("Create Cluster Stack definition (CSP/per tenant)")


## Cleaning up

1. Delete the cluster resource like so (kubectl targets the Cluster Stacks management cluster): `kubectl -n hkthn delete clusters hkthn-cluster`
2. Delete the KinD cluster (run on local machine): `kind delete clusters hkthn`


## Additional notes

### OpenStack CLI client

If you have the OpenStack CLI client installed, you can also make use of the `app-cred-*-openrc.sh` file:

1. `source <(openstack complete)`
2. `source app-cred-*-openrc.sh`

The CLI tool helps with cleaning up OpenStack resources if something went wrong and the UI is too annoying.

### Cilium in workload k8s cluster

The networking in the workload clusters is managed by Cilium.

Via kubectl, you can for example check the state with: `kubectl -n kube-system exec -ti cilium-4ww5k -- cilium status`.

Of course you can also install the `cilium` binary on your local machine and aim it at the workload cluster as well.
