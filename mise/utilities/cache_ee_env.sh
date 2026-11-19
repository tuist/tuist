# External contributors can't reach the cache, so it is off by default (Tuist.swift). A Tuist credential, such as the
# TUIST_OIDC_TOKEN every command on a Tuist sandbox gets, or a member's checkout of the private submodule turns it on.
if [[ -n "${TUIST_TOKEN:-}${TUIST_OIDC_TOKEN:-}" ]]; then
  export TUIST_ENABLE_CACHING="${TUIST_ENABLE_CACHING:-1}"
fi
if [[ -d "${MISE_CONFIG_ROOT}/cli/TuistCacheEE/Sources" ]]; then
  # A job can turn caching off by setting TUIST_ENABLE_CACHING itself.
  export TUIST_ENABLE_CACHING="${TUIST_ENABLE_CACHING:-1}"
  export TUIST_EE=1
fi
