#!/bin/sh

# Full setup script based on the quickstart in https://github.com/SovereignCloudStack/cluster-stacks.
# Built for use in Arnsberg Hackathon on 2024-04-16, hence the names.
# Author: Dominik Pataky <pataky@osb-alliance.com> 2024-04

set -e

debug () {
    echo
    d=$(date +%H:%M:%S)
    echo -e "${d} | $@"
}

debug "Setting git PAT from file"
export GH_PAT=$(cat gh-pat | tr --delete '[:space:]')

debug "Setting git env vars"
export GIT_PROVIDER_B64=Z2l0aHVi  # github
export GIT_ORG_NAME_B64=U292ZXJlaWduQ2xvdWRTdGFjaw== # SovereignCloudStack
export GIT_REPOSITORY_NAME_B64=Y2x1c3Rlci1zdGFja3M=  # cluster-stacks
export GIT_ACCESS_TOKEN_B64=$(echo -n ${GH_PAT} | base64 -w0)

debug "Create KinD cluster to be used as ClusterStacks management cluster"
kind create cluster --name hkthn --kubeconfig kubeconfig_hkthn_capi

debug "Setting generated kubeconfig"
export KUBECONFIG=$(pwd)/kubeconfig_hkthn_capi

debug "clusterctl init on OpenStack"
export CLUSTER_TOPOLOGY=true
export EXP_CLUSTER_RESOURCE_SET=true
clusterctl init --infrastructure openstack

debug "Fetching and applying CSO to KinD cluster"
# https://github.com/SovereignCloudStack/cluster-stack-operator/releases
export CSO_VERSION=v0.1.0-alpha.5
export CSO_FILE=$(python3 fetch-cso-cspo.py cso)
kubectl apply -f $CSO_FILE

debug "Fetching, patching and applying CSPO to KinD cluster"
# https://github.com/SovereignCloudStack/cluster-stack-provider-openstack/releases
export CSPO_VERSION=v0.1.0-alpha.3
export CSPO_FILE=$(python3 fetch-cso-cspo.py cspo)
kubectl apply -f $CSPO_FILE

CSP_HELPER_URL=https://github.com/SovereignCloudStack/cluster-stacks/releases/download/openstack-csp-helper-v0.3.0/openstack-csp-helper.tgz
debug "Init CSP helper"
until helm upgrade -i csp-helper-hkthn -n hkthn --create-namespace $CSP_HELPER_URL -f clouds.yaml
do
    debug "Trying again in three seconds.."
    sleep 3
done

debug "Run kubectl for clusterstack definition"
kubectl apply -f clusterstack_def.yaml

debug "Wait for ClusterClass 'openstack-alpha-1-28-v3' to become available (timeout at 120s)"
until kubectl -n hkthn wait --timeout=120s --for=condition=READY clusterstackreleases.clusterstack.x-k8s.io openstack-alpha-1-28-v3
do
    debug "Checking again in three seconds.."
    sleep 3
done

debug "Run kubectl for cluster definition"
kubectl apply -f cluster_def.yaml

debug "Check cluster"
until clusterctl -n hkthn describe cluster hkthn-cluster --grouping=false --show-resourcesets --show-machinesets
do
    debug "Trying again in three seconds.."
    sleep 3
done

debug "You can now fetch the kubeconfig with 'clusterctl -n hkthn get kubeconfig hkthn-cluster > kubeconfig_hkthn_workload'"
debug "View the cluster: clusterctl -n hkthn describe cluster hkthn-cluster --grouping=false --show-resourcesets  --show-machinesets"
