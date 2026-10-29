if [[ -d "${MISE_CONFIG_ROOT}/cli/TuistCacheEE/Sources" ]]; then
  # A job can turn caching off by setting TUIST_ENABLE_CACHING itself.
  export TUIST_ENABLE_CACHING="${TUIST_ENABLE_CACHING:-1}"
  export TUIST_EE=1
fi
