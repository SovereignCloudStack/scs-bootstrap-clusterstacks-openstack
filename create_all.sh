#!/bin/sh

# Full setup script based on the quickstart in https://github.com/SovereignCloudStack/cluster-stacks.
# URL: https://github.com/SovereignCloudStack/cluster-stacks/blob/6b250211290c181aa3a3c14831b4bcc665b8a811/providers/openstack/README.md

# Built for use in Arnsberg Hackathon on 2024-04-16 and extended for multiple environments.
# Author: Dominik Pataky <pataky@osb-alliance.com> 2024

set -e

debug () {
    d=$(date +%H:%M:%S)
    echo -e "🔵 ${d} | $@"
}

CLOUDSYAML=$1

if [[ -z "$CLOUDSYAML" ]]; then
    debug "No specific clouds.yaml was passed as argument, using default 'clouds.yaml' file name"
    CLOUDSYAML="clouds.yaml"
fi

if [[ ! -f "$CLOUDSYAML" ]]; then
    debug "Tried to use file '$CLOUDSYAML' as clouds.yaml, but file does not exist or is not a file"
    exit 1
fi

if ! grep 'clouds:' "$CLOUDSYAML" >/dev/null; then
    debug "File '$CLOUDSYAML' does not contain a 'clouds:' section. Please check your clouds.yaml file"
    exit 1
fi

debug "Using file '$CLOUDSYAML' as the clouds.yaml source"

if [[ ! -f "gh-pat" ]]; then
    debug "You must have a file named 'gh-pat' in this directory"
    exit 1
fi

if ! which clusterctl >/dev/null; then
    debug "You need to have the clusterctl binary in your PATH"
    exit 1
fi

read -r -p "🔴 Please enter your OpenStack public network interface UUID: " OS_PUBLIC_INTERFACE_UUID

debug "Reading Github personal access token from file, storing as env var"
export GH_PAT=$(cat gh-pat | tr --delete '[:space:]')


debug "Setting Github related env vars"
export GIT_PROVIDER_B64=Z2l0aHVi  # github
export GIT_ORG_NAME_B64=U292ZXJlaWduQ2xvdWRTdGFjaw== # SovereignCloudStack
export GIT_REPOSITORY_NAME_B64=Y2x1c3Rlci1zdGFja3M=  # cluster-stacks
export GIT_ACCESS_TOKEN_B64=$(echo -n ${GH_PAT} | base64 -w0)


debug "Create KinD cluster to be used as ClusterStacks management cluster"
KIND_CLUSTER_NAME="cluster-stacks-bootstrapper"
KUBECONFIG_NAME="kubeconfig_$KIND_CLUSTER_NAME"

if kind get clusters --quiet | grep "$KIND_CLUSTER_NAME" >/dev/null; then
    # KinD cluster already exists, ask if it should be used
    debug "KinD cluster $KIND_CLUSTER_NAME already exists."
    read -p "Do you want to continue with the existing KinD cluster? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        debug "Aborting, please delete KinD cluster before running again"
        exit 1
    fi
else
    # Create KinD cluster if not existing
    kind create cluster --name "$KIND_CLUSTER_NAME" --kubeconfig "$KUBECONFIG_NAME"
fi


debug "Setting generated kubeconfig"
export KUBECONFIG="$(pwd)/$KUBECONFIG_NAME"


debug "clusterctl init on OpenStack"
export CLUSTER_TOPOLOGY=true
export EXP_CLUSTER_RESOURCE_SET=true
export EXP_RUNTIME_SDK=true
clusterctl init --infrastructure openstack


debug "Fetching and applying CSO to KinD cluster"
# https://github.com/SovereignCloudStack/cluster-stack-operator/releases
export CSO_VERSION=v0.1.0-alpha.6
export CSO_FILE=$(python3 fetch-cso-cspo.py cso)

debug "Got $CSO_FILE as the patched file, to be read into kubectl apply"
until kubectl apply -f "$CSO_FILE"
do
    debug "Expected race condition met, trying again in three seconds.."
    sleep 3
done


debug "Fetching, patching and applying CSPO to KinD cluster"
# https://github.com/SovereignCloudStack/cluster-stack-provider-openstack/releases
export CSPO_VERSION=v0.1.0-alpha.3
export CSPO_FILE=$(python3 fetch-cso-cspo.py cspo)

debug "Got $CSPO_FILE as the patched file, to be read into kubectl apply"
kubectl apply -f "$CSPO_FILE"


TENANT="scs-bootstrapped-tenant-$RANDOM"
debug "Define namespace name for tenant as $TENANT"
export CS_NAMESPACE=$TENANT



CSP_HELPER_URL="https://github.com/SovereignCloudStack/openstack-csp-helper/releases/download/v0.6.0/openstack-csp-helper.tgz"
debug "Init CSP helper"
until helm upgrade -i "csp-helper-$CS_NAMESPACE" -n "$CS_NAMESPACE" --create-namespace $CSP_HELPER_URL -f "$CLOUDSYAML"
do
    debug "Trying again in three seconds.."
    sleep 3
done


# the name of the cluster stack (must match a name of a directory in https://github.com/SovereignCloudStack/cluster-stacks/tree/main/providers/openstack)
export CS_NAME=alpha
# the kubernetes version of the cluster stack (must match a tag for the kubernetes version and the stack version)
export CS_K8S_VERSION=1.29
# the version of the cluster stack (must match a tag for the kubernetes version and the stack version)
export CS_VERSION=v2
export CS_CHANNEL=stable
# must match a cloud section name in the used clouds.yaml
export CS_CLOUDNAME=openstack
export CS_SECRETNAME="${CS_CLOUDNAME}"

debug "Creating clusterstack.generated.yaml"
cat > clusterstack.generated.yaml <<EOF
apiVersion: clusterstack.x-k8s.io/v1alpha1
kind: ClusterStack
metadata:
  name: clusterstack
  namespace: ${CS_NAMESPACE}
spec:
  provider: openstack
  name: ${CS_NAME}
  kubernetesVersion: "${CS_K8S_VERSION}"
  channel: ${CS_CHANNEL}
  autoSubscribe: false
  providerRef:
    apiVersion: infrastructure.clusterstack.x-k8s.io/v1alpha1
    kind: OpenStackClusterStackReleaseTemplate
    name: cspotemplate
  versions:
    - ${CS_VERSION}
---
apiVersion: infrastructure.clusterstack.x-k8s.io/v1alpha1
kind: OpenStackClusterStackReleaseTemplate
metadata:
  name: cspotemplate
  namespace: ${CS_NAMESPACE}
spec:
  template:
    spec:
      identityRef:
        kind: Secret
        name: ${CS_SECRETNAME}
EOF

debug "Run kubectl for clusterstack definition"
until kubectl apply -f clusterstack.generated.yaml
do
    debug "Expected race condition met, trying again in three seconds.."
    sleep 3
done


# Name of the ClusterClass resource
export CS_CLASS_NAME=openstack-"${CS_NAME}"-"${CS_K8S_VERSION/./-}"-"${CS_VERSION}"

# Wait for it
debug "Wait for ClusterClass $CS_CLASS_NAME to become available (timeout at 60s)"
until kubectl -n "$CS_NAMESPACE" wait --timeout=60s --for=condition=READY clusterstackreleases.clusterstack.x-k8s.io "$CS_CLASS_NAME"
do
    debug "Waiting for ClusterClass. Checking again in three seconds.."
    sleep 3
done

# Now continue with submitting a Cluster based on this ClusterClass
export CS_CLUSTER_NAME=cs-cluster
export CS_POD_CIDR=192.168.0.0/16
export CS_SERVICE_CIDR=10.96.0.0/12
export CS_EXTERNAL_ID="$OS_PUBLIC_INTERFACE_UUID"
export CS_K8S_PATCH_VERSION=3

debug "Creating cluster.generated.yaml"
cat > cluster.generated.yaml <<EOF
apiVersion: cluster.x-k8s.io/v1beta1
kind: Cluster
metadata:
  name: ${CS_CLUSTER_NAME}
  namespace: ${CS_NAMESPACE}
  labels:
    managed-secret: cloud-config
spec:
  clusterNetwork:
    pods:
      cidrBlocks:
        - ${CS_POD_CIDR}
    serviceDomain: cluster.local
    services:
      cidrBlocks:
        - ${CS_SERVICE_CIDR}
  topology:
    variables:
      - name: controller_flavor
        value: "SCS-2V-4-50"
      - name: worker_flavor
        value: "SCS-2V-4-50"
      - name: external_id
        value: ${CS_EXTERNAL_ID}
    class: ${CS_CLASS_NAME}
    controlPlane:
      replicas: 1
    version: v${CS_K8S_VERSION}.${CS_K8S_PATCH_VERSION}
    workers:
      machineDeployments:
        - class: ${CS_CLASS_NAME}
          failureDomain: nova
          name: ${CS_CLASS_NAME}
          replicas: 2
EOF

debug "Run kubectl for cluster definition"
kubectl apply -f cluster.generated.yaml

debug "Check created workload cluster"
until clusterctl -n "${CS_NAMESPACE}" describe cluster "${CS_CLUSTER_NAME}" --grouping=false --show-resourcesets --show-machinesets
do
    debug "Checking created workload cluster. Trying again in three seconds.."
    sleep 3
done

echo
debug "All done. Your SCS tenant namespace is '$TENANT'"
debug "You can now fetch the kubeconfig with \"clusterctl -n ${CS_NAMESPACE} get kubeconfig ${CS_CLUSTER_NAME} > kubeconfig_workload_cluster\""
debug "View the cluster: clusterctl -n ${CS_NAMESPACE} describe cluster ${CS_CLUSTER_NAME} --grouping=false --show-resourcesets --show-machinesets"
