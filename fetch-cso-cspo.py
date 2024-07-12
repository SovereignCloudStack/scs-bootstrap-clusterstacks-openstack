"""
Helper script for the setup in https://github.com/SovereignCloudStack/cluster-stacks.
Replaces the proposed envsubst tool that is used in the quick start guide.

Author: Dominik Pataky <pataky@osb-alliance.com> 2024-04
"""

import urllib.request
import os
import sys

try:
    import yaml
except ImportError:
    print("Python needs to import 'yaml', install package PyYAML")
    exit(3)

class Modes:
    """
    Wrapper class around modes that are passed in via sys.argv
    """
    CSO = 1
    CSPO = 2

    @classmethod
    def from_str(cls, arg):
        if arg == "cso":
            return cls.CSO
        if arg == "cspo":
            return cls.CSPO
        return None

def usage():
    print("Usage: python3 fetch-cso-cspo.py cso|cspo")
    exit(2)

if __name__ == "__main__":
    # Set and check the version env vars
    CSO_VERSION = os.environ.get("CSO_VERSION")
    CSPO_VERSION = os.environ.get("CSPO_VERSION")
    if not any([CSO_VERSION, CSPO_VERSION]):
        print("Neither CSO_VERSION nor CSPO_VERSION are set")
        exit(1)

    # Set and check the git related env vars
    GIT_ACCESS_TOKEN_B64=os.environ.get("GIT_ACCESS_TOKEN_B64")
    GIT_ORG_NAME_B64=os.environ.get("GIT_ORG_NAME_B64")
    GIT_PROVIDER_B64=os.environ.get("GIT_PROVIDER_B64")
    GIT_REPOSITORY_NAME_B64=os.environ.get("GIT_REPOSITORY_NAME_B64")
    if not all([GIT_ACCESS_TOKEN_B64, GIT_ORG_NAME_B64, GIT_PROVIDER_B64, GIT_REPOSITORY_NAME_B64]):
        print("Not all GIT_ vars were set")
        exit(1)

    # Check that a mode was passed in
    if len(sys.argv) < 2:
        usage()

    # Get mode from command line argument
    arg = sys.argv[1]
    mode = Modes.from_str(arg)
    if not mode:
        usage()

    # Set resource yaml URL according to mode
    if mode == Modes.CSO:
        url_to_get = f"https://github.com/SovereignCloudStack/cluster-stack-operator/releases/download/{CSO_VERSION}/cso-infrastructure-components.yaml"
    elif mode == Modes.CSPO:
        url_to_get = f"https://github.com/sovereignCloudStack/cluster-stack-provider-openstack/releases/download/{CSPO_VERSION}/cspo-infrastructure-components.yaml"

    # Retrieve the YAML file and store it in a local file with random file name
    try:
        local_filename, headers = urllib.request.urlretrieve(url_to_get)
    except Exception as ex:
        print(f"There was an exception during downloading of URL: {ex}")
        exit(3)

    # A list of YAML documents that will be written to the resulting YAML file
    docs_to_write = list()
    with open(local_filename) as fh:
        # Load all YAML documents from the file
        docs = yaml.safe_load_all(fh)

        # We aim to fetch exactly one document that contains the ENV vars that would normally be substituted by Go envsubst
        doc_to_patch = None

        matched = False
        for doc in docs:
            # Use "endswith" to match both CSO and CSPO
            if doc.get("kind") == "Secret" and doc["metadata"].get("name").endswith("-cluster-stack-variables"):
                if matched:
                    print(f"There was a second match on the cluster-stack-variables secret section!")
                    exit(4)
                # On match, store it separately
                doc_to_patch = doc
                matched = True
            else:
                # No match, just pass through
                docs_to_write.append(doc)

        if not matched or doc_to_patch is None:
            print(f"There was no match on doc_to_patch")
            exit(5)

        # Now do the patching
        doc_to_patch["data"] = {
            'git-access-token': f'{GIT_ACCESS_TOKEN_B64}',
            'git-org-name': f'{GIT_ORG_NAME_B64}',
            'git-provider': f'{GIT_PROVIDER_B64}',
            'git-repo-name': f'{GIT_REPOSITORY_NAME_B64}'
        }

        # And add the patched document to the rest of the documents
        docs_to_write.append(doc_to_patch)

    # Take the random file name as base and add suffix
    new_filename = f"{local_filename}_patched"

    # Dump all documents we want to write into it. Order does not matter
    with open(new_filename, "w") as fh:
        yaml.safe_dump_all(docs_to_write, fh, default_flow_style=False)

    # Output the file name without trailing newline so that the shell
    # script can pick up the stdout for exported variable in the script.
    print(new_filename, end='')
