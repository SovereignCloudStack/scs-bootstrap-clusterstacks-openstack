# Automated setup script for Cluster Stacks on OpenStack

This script bootstraps Cluster Stacks on OpenStack, namely the SCS gx-scs environment.

Quick-start source: [cluster-stacks/providers/openstack/README.md](https://github.com/SovereignCloudStack/cluster-stacks/blob/6b250211290c181aa3a3c14831b4bcc665b8a811/providers/openstack/README.md).

Run `create_all.sh` with bash or zsh and follow the displayed instructions.

## Pre-requirements

### CLI tools

As stated in the source README, you need the following CLI tools:

* `kind` (works with both Docker and Podman)
* `kubectl`
* `helm`
* `clusterctl`
* `jq`

Go with `envsubst` is not needed here because it is replaced with Python.


### Config files

* `gh-pat`: plain text file that contains your Github PAT
* `clouds.yaml`: credentials from your OpenStack project


## Cleaning up

1. Delete the cluster resource like so (kubectl targets the Cluster Stacks management cluster): `kubectl -n scs-tenant delete cluster cs-cluster`
2. Delete the KinD cluster (run on local machine): `kind delete clusters cluster-stacks-bootstrapper`


## Additional notes

### OpenStack CLI client

If you have the OpenStack CLI client installed, you can make use of the `app-cred-*-openrc.sh` file you get from Horizon:

1. `source <(openstack complete)`
2. `source app-cred-*-openrc.sh`

The CLI tool helps with cleaning up OpenStack resources if something went wrong and the UI is too annoying.

Example: Delete all ports in a project, which are marked as `DOWN`:

```shell
openstack port list --long --format value | grep DOWN | awk '{ print $1 }' | xargs -L 1 openstack port delete
```

### Cilium in workload k8s cluster

The networking in the workload clusters is managed by Cilium.

Via kubectl, you can check Cilium state in the workload cluster with: `kubectl -n kube-system exec -ti cilium-4ww5k -- cilium status` (where `-4ww5k` is to be replaced by the pod name).

Of course you can also install the `cilium` CLI binary on your local machine and aim it at the workload cluster as well.
