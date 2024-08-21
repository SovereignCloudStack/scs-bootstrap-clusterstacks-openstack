#!bash

# SPDX-License-Identifier: Apache-2.0

# Copyright 2024 Dominik Pataky
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


set -e

FILENAME="$0"

debug() {
    TS=$(date +%H:%M:%S)
    echo "[$TS] $1"
}

usage() {
  echo "Usage: $FILENAME <username> <namespace> <cluster_server> <cluster_cert_authority_file>"
  echo "Example: $FILENAME new_user testing_namespace https://127.0.0.1:6443 ./cluster_ca.crt"
}

# Quick confirmation func
ask_confirmation() {
  read -p "Do you want to continue? (y/n) " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    debug "Aborting"
    exit 1
  fi
}

# Start by checking that KUBECONFIG is set
if [[ -z "$KUBECONFIG" ]]; then
  echo "Environment variable KUBECONFIG is not set"
  exit
fi

# Sanity check on arguments
USERNAME="$1"
if test -z "$USERNAME"; then usage; exit; fi
NAMESPACE="$2"
if test -z "$NAMESPACE"; then usage; exit; fi
CLUSTER_SERVER="$3"
if test -z "$CLUSTER_SERVER"; then usage; exit; fi
CLUSTER_CERT_AUTHORITY_DATA_FILE="$4"
if test -z "$CLUSTER_CERT_AUTHORITY_DATA_FILE"; then usage; exit; fi
debug "Username set as '$USERNAME', namespace as '$NAMESPACE'. Config will be built for cluster $CLUSTER_SERVER, certificate data read from $CLUSTER_CERT_AUTHORITY_DATA_FILE"
ask_confirmation

if [[ ! -f "$CLUSTER_CERT_AUTHORITY_DATA_FILE" ]]; then
    echo "$CLUSTER_CERT_AUTHORITY_DATA_FILE is not an existing file"
    exit
fi

# And sanity check for kubeconfig.
# This will be used to create the certificate signing request, the role and rolebinding
debug "Using kubeconfig: $KUBECONFIG"
ask_confirmation

KEYNAME="$USERNAME.generated.key"
if [[ -f "$KEYNAME" ]]; then
  echo "$KEYNAME already exists, won't override. Aborting"
  exit
fi

# Generates a new private key with RSA 2048. For testing purposes only, use stronger keys in production.
debug "Generating secret key"
openssl genrsa -out "$KEYNAME" 2048

# Generate CSR to be sent to Kubernetes API
debug "Generating CSR from secret key"
CSRNAME="$USERNAME.generated.csr"
openssl req -new -key "$KEYNAME" -out "$CSRNAME" -subj "/CN=$USERNAME"

debug "Converting CSR to base64 format"
B64CSRNAME="$USERNAME.base64.generated.csr"
base64 < "$CSRNAME" | tr -d "\n" > "$B64CSRNAME"

# And send it to API via a new CertificateSigningRequest
# expirationSeconds 86400 = one day, 2592000 = 30 days, 7776000 = 90 days
debug "Applying CertificateSigningRequest to Kube API"
cat <<EOF | kubectl apply -f -
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: $USERNAME
spec:
  groups:
  - system:authenticated
  request: $(cat "$B64CSRNAME")
  signerName: kubernetes.io/kube-apiserver-client
  expirationSeconds: 7776000
  usages:
  - client auth
EOF

# Approve the uploaded certificate signing request
debug "Approving cert.."
kubectl certificate approve "$USERNAME"

# And fetch the signed certificate to be included in the kubeconfig
debug "Fetching approved cert"
CERTNAME="$USERNAME.generated.crt"
kubectl get certificatesigningrequests "$USERNAME" -o jsonpath='{ .status.certificate }' | base64 --decode > "$CERTNAME"


# Generate a new kubeconfig for this new "user"
debug "Creating new kubeconfig file locally"
NEWCONFIG="$USERNAME.kubeconfig.generated.yaml"
kubectl --kubeconfig="$NEWCONFIG" config set-cluster "kubernetes-$USERNAME" --server="$CLUSTER_SERVER" --certificate-authority="$CLUSTER_CERT_AUTHORITY_DATA_FILE" --embed-certs=true
kubectl --kubeconfig="$NEWCONFIG" config set-credentials "$USERNAME" --client-key="$KEYNAME" --client-certificate="$CERTNAME" --embed-certs=true
kubectl --kubeconfig="$NEWCONFIG" config set-context "$USERNAME@kubernetes-$USERNAME" --cluster="kubernetes-$USERNAME" --user="$USERNAME" --namespace="$NAMESPACE"
kubectl --kubeconfig="$NEWCONFIG" config use-context "$USERNAME@kubernetes-$USERNAME"


# Now we first need a new role in the namespace with all permissions (namespace scope)
debug "Creating and applying Role"
cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: $USERNAME-role
  namespace: $NAMESPACE
rules:
- apiGroups:
  - "*"
  resources:
  - "*"
  verbs:
  - "*"
EOF

# And then create a role binding to connect the certificate name (as given in the CN name) to the role
debug "Creating and applying RoleBinding"
cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: $USERNAME-rolebinding
  namespace: $NAMESPACE
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: $USERNAME-role
subjects:
- apiGroup: rbac.authorization.k8s.io
  kind: User
  name: $USERNAME
EOF


# Now some cluster roles
debug "Creating and applying ClusterRole and ClusterRoleBinding"
cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: "users:$USERNAME-clusterrole"
rules:
- apiGroups:
  - '*'
  resources:
  - pvc
  - pv
  - nodes
  verbs:
  - "get"
  - "list"
  - "watch"
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: $USERNAME-clusterrolebinding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: "users:$USERNAME-clusterrole"
subjects:
- apiGroup: rbac.authorization.k8s.io
  kind: User
  name: "$USERNAME"
EOF

echo
debug "All done!"
