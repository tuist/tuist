#!/usr/bin/env python3
"""Clone a storage class for disposable restore data, never the live volume."""

import copy
import json
import sys


def recovery_storage_class(source, name):
    if not name.startswith("pg-restore-drill-") or name == source["metadata"]["name"]:
        raise ValueError("Recovery storage must have its own drill-scoped name")
    if not source.get("provisioner"):
        raise ValueError("Source storage class has no provisioner")
    fields = ["provisioner", "parameters", "mountOptions", "allowVolumeExpansion",
              "volumeBindingMode", "allowedTopologies"]
    result = {key: copy.deepcopy(source[key]) for key in fields if key in source}
    result.update({
        "apiVersion": "storage.k8s.io/v1",
        "kind": "StorageClass",
        "metadata": {"name": name, "labels": {"purpose": "cnpg-restore-drill"}},
        "reclaimPolicy": "Delete",
    })
    return result


if __name__ == "__main__":
    with open(sys.argv[1]) as source:
        print(json.dumps(recovery_storage_class(json.load(source), sys.argv[2])))
