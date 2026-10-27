# shellcheck shell=bash

export KURA_PROJECT_ROOT="${PWD}"

spec_helper_precheck() {
  minimum_version "0.28.1"
  if [ "$SHELL_TYPE" != "bash" ]; then
    abort "Kura e2e specs require bash"
  fi
}

spec_helper_loaded() {
  :
}

spec_helper_configure() {
  :
}
