#!/usr/bin/env bash
set -euo pipefail

settings=$(helm get values "${HELM_RELEASE_NAME:?}" -n "${NAMESPACE:?}" --all -o json |
    jq -c '.kuraController | {enabled: (.enabled and .stableDNS.enabled), namespace, certificate: .publicWildcardCertificate.secretName}')
if ! jq -e '.enabled == true' <<< "$settings" >/dev/null; then
    echo 'Stable cache DNS is disabled; skipping its certificate gate.'
    exit 0
fi

namespace=$(jq -er '.namespace' <<< "$settings")
certificate=$(jq -er '.certificate' <<< "$settings")
for attempt in $(seq 1 60); do
    if state=$(kubectl -n "$namespace" get certificate "$certificate" -o json --request-timeout=10s) &&
        jq -e '
            .metadata.generation as $generation |
            (.spec.dnsNames | index("*.cache.tuist.dev") != null) and
            (.spec.dnsNames | index("*.kura.tuist.dev") != null) and
            any(.status.conditions[]?;
                .type == "Ready" and .status == "True" and .observedGeneration == $generation)
        ' <<< "$state" >/dev/null; then
        echo 'Stable cache wildcard certificate is Ready at the current generation.'
        exit 0
    fi
    echo "Waiting for the updated stable cache wildcard certificate ($attempt/60)."
    sleep 10
done

echo 'ERROR: stable cache certificate is not Ready; stop the environment promotion.' >&2
exit 1
