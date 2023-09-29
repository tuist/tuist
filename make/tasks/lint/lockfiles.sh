#!/bin/bash

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ROOT_DIR=$($SCRIPT_DIR/../../utilities/root_dir.sh)

assert_same_packages_count() {
    spm_count=$(jq '.pins | length' "$spm_lockfile")
    tuist_count=$(jq '.pins | length' "$tuist_lockfile")

    if [ "$spm_count" -ne "$tuist_count" ]; then
        echo "The number of packages in the Package.resolved files don't match."
        return 1
    fi
    return 0
}

assert_same_versions() {
    mismatched_packages=()

    for package_name in $(jq -r '.pins[] .identity' "$spm_lockfile"); do
        if jq -e ".pins[] | select(.identity == \"$package_name\")" "$tuist_lockfile" > /dev/null; then
            tuist_revision=$(jq -r ".pins[] | select(.identity == \"$package_name\") .state.revision" "$tuist_lockfile")
            spm_revision=$(jq -r ".pins[] | select(.identity == \"$package_name\") .state.revision" "$spm_lockfile")

            if [ "$tuist_revision" != "$spm_revision" ]; then
                mismatched_packages+=("$package_name")
            fi
        fi
    done

    if [ "${#mismatched_packages[@]}" -ne 0 ]; then
        echo "There's a mismatch between the revision of the following packages in the Package.resolved files: ${mismatched_packages[*]}"
        return 1
    fi

    return 0
}

spm_lockfile="$ROOT_DIR/Package.resolved"
tuist_lockfile="$ROOT_DIR/Tuist/Dependencies/Lockfiles/Package.resolved"

assert_same_packages_count
status1=$?

assert_same_versions
status2=$?

if [ $status1 -ne 0 ] || [ $status2 -ne 0 ]; then
    exit 1
fi
