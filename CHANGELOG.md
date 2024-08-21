# Changelog

## v0.3.0 - 2024-08-21

New release with better error handling, custom cloud.yaml and a script for generating kubeconfigs with their own certificate-based RBAC config.

This Cluster Stacks bootstrapping script has been part of deployment tests in at least five different OpenStack environments and reached a good state of maturity.

Published under Apache-2.0 license.

### Changed

- **Breaking**: The tenant, namespace and cluster will now have a `$RANDOM_NUMBER` suffix in their names, to distinguish created resources in between multiple runs of the script (detecting of something was left over from previous executions)
- `CSPO_VERSION` is now `v0.1.0-alpha.4`

### Added

- The `clouds.yaml` file from OpenStack can now be given as a parameter: `create_all.sh my-second-clouds.yaml`. If not given, the local `clouds.yaml` file will be used
- A second script was added to quickly generate kubeconfigs for additional access to the workload cluster. See the README in the `generate-cert-access` folder.

### Fixed

- Workload clusters will now use the `SCS-2V-4-20s` VM flavor for controller_flavor and worker_flavor, instead of the previously used `SCS-2V-4-50` flavor. Reason being, that the `-20s` is mandatory, the `-50` is not. This caused some environments to fail because the flavor could not be used.




## v0.2.0 - 2024-07-12

_First tag in repo, changelog highlights changes from initial commit 37ad296 from 2024-04-15._

Update bootstrapping script to Cluster Stacks openstack-alpha-1-29-v2.


### Changed
- `CSO_VERSION` is now `v0.1.0-alpha.6`
- CSP helper uses the new repo at `https://github.com/SovereignCloudStack/openstack-csp-helper`
- Hardcoded names for resources (example `hkthn` or `hkthn-cluster`) are replaced by variables with pre-defined defaults (example `scs-tenant` for namespace)

### Added
- More checks for existence of files
- Checking any existing KinD cluster, asking whether the user wants to re-use an existing one (helpful, if the result of re-creating it would be the same)
- Query the OpenStack public network interface UUID from the user at the beginning of script execution
- Check in `fetch-cso-cspo.py` for handling no-match or multi-match of the patched cluster-stack-variables secret

### Removed
- Removed `cluster_def.yaml` and `clusterstack_def.yaml` as external files, they are included in the script itself now

### Fixed
- Generated files now contain the `.generated.` infix in their file names

