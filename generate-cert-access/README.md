# Generator for cert-based cluster authentication

With this script, you can generate **a new certificate-based Kubeconfig** which has **RBAC rules for specific namespaces and some cluster resources**.

This is basically a way to create new "users" with some limitations so that you do not have to share the cluster-admin config.

**Warning**: The `openssl genrsa` command generates a secret RSA key locally and later puts it into the Kubeconfig. This means that the secret key of the certificate is shared among multiple people. **Only use this script for testing purposes, e.g. for cluster access in Cluster Stacks testing environments** (workload clusters).

## What is covered

1. Generate a secret RSA key
1. Generate a CSR from secret RSA key
1. Convert the CSR to base64 format
1. Create a CertificateSigningRequest in Kubernetes with the user_name as `CN`
1. Approve the CertificateSigningRequest
1. Fetch the approved cert from Kubernetes
1. Create the new kubeconfig file
1. Configure Role, RoleBinding, ClusterRole and ClusterRoleBinding for the user_name


## Usage

Requirements:

* A working Kubeconfig for your workload cluster with `cluster-admin` role. Export this one as your `KUBECONFING` env variable.
* A namespace in the workload cluster that shall be used for the new Kubeconfig. Create with: `kubectl create ns <namespace_name>`.

If all requirements are fulfilled, the following steps guide you through the script:

1. Fetch the value `certificate-authority-data` from your existing Kubeconfig and convert it from base64 to a text file. Example: `echo "LS...tLQo=" | base64 -d > my_cluster_cad.crt`. This file `my_cluster_cad.crt` will then begin with the line `-----BEGIN CERTIFICATE-----`.
1. Fetch the value `server` from your existing Kubeconfig. Example: `https://127.0.0.1:6443`.
1. Run the script with your parameters: `bash create_user_with_cert.sh <user_name> <namespace_name> <server> <cad_file_path>`. Example: `bash create_user_with_cert.sh testuser testing-ns https://127.0.0.1:6443 ./my_cluster_cad.crt`
1. Confirm the two sanity check prompts.

Now the script runs and does the things listed above.



## References

* <https://kubernetes.io/docs/reference/access-authn-authz/rbac/>
* <https://kubernetes.io/docs/reference/access-authn-authz/certificate-signing-requests/>
