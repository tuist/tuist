if [[ -d "${MISE_CONFIG_ROOT}/cli/TuistCacheEE/Sources" ]]; then
  # A job can turn caching off; the Coverage workflow does, since cached compilations carry no coverage.
  export TUIST_ENABLE_CACHING="${TUIST_ENABLE_CACHING:-1}"
  export TUIST_EE=1
fi
