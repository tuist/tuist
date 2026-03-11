{
  bash,
  coreutils,
  lib,
  stdenvNoCC,
  fetchurl,
  nodeRuntimes ? [
    "node20"
    "node24"
  ],
}: let
  version = "2.332.0";
in
  stdenvNoCC.mkDerivation {
    pname = "github-runner-binary";
    inherit version;
    dontUnpack = true;

    src = fetchurl {
      url = "https://github.com/actions/runner/releases/download/v${version}/actions-runner-osx-arm64-${version}.tar.gz";
      hash = "sha256-1TvtswYZpk51G7n3KcyemzXrHfU2FlHVTargDbM/LnM=";
    };

    nativeBuildInputs = [
      bash
      coreutils
    ];

    installPhase = ''
      runHook preInstall

      mkdir -p "$TMPDIR/runner"
      tar -xzf "$src" -C "$TMPDIR/runner"

      mkdir -p "$out/lib/github-runner-template" "$out/bin"
      cp -R "$TMPDIR/runner/." "$out/lib/github-runner-template"
      chmod -R u+w "$out/lib/github-runner-template"

      enabled_node_runtimes=" ${lib.concatStringsSep " " nodeRuntimes} "

      if [[ "$enabled_node_runtimes" != *" node20 "* ]]; then
        rm -rf "$out/lib/github-runner-template/externals/node20"
      fi

      if [[ "$enabled_node_runtimes" != *" node24 "* ]]; then
        rm -rf "$out/lib/github-runner-template/externals/node24"
      fi

      cat > "$out/bin/github-runner-ensure-root" <<'EOF'
      #!${bash}/bin/bash
      set -euo pipefail

      if [[ -z "''${RUNNER_ROOT:-}" ]]; then
        echo "RUNNER_ROOT must be set" >&2
        exit 1
      fi

      script_dir=$(cd "$(dirname "$0")" && pwd)
      template=$(cd "$script_dir/../lib/github-runner-template" && pwd)

      if [[ ! -x "''${RUNNER_ROOT}/bin/Runner.Listener" ]]; then
        mkdir -p "''${RUNNER_ROOT}"
        ${coreutils}/bin/cp -R "''${template}/." "''${RUNNER_ROOT}/"
        ${coreutils}/bin/chmod -R u+w "''${RUNNER_ROOT}"
      fi
      EOF
      chmod +x "$out/bin/github-runner-ensure-root"

      cat > "$out/bin/config.sh" <<'EOF'
      #!${bash}/bin/bash
      set -euo pipefail
      script_dir=$(cd "$(dirname "$0")" && pwd)
      "$script_dir/github-runner-ensure-root"
      exec "''${RUNNER_ROOT}/config.sh" "$@"
      EOF
      chmod +x "$out/bin/config.sh"

      cat > "$out/bin/Runner.Listener" <<'EOF'
      #!${bash}/bin/bash
      set -euo pipefail
      script_dir=$(cd "$(dirname "$0")" && pwd)
      "$script_dir/github-runner-ensure-root"
      exec "''${RUNNER_ROOT}/bin/Runner.Listener" "$@"
      EOF
      chmod +x "$out/bin/Runner.Listener"

      ln -s "$out/lib/github-runner-template/env.sh" "$out/bin/env.sh"
      ln -s "$out/lib/github-runner-template/run.sh" "$out/bin/run.sh"

      runHook postInstall
    '';

    meta = {
      description = "Binary-packaged GitHub Actions runner for macOS";
      homepage = "https://github.com/actions/runner";
      license = lib.licenses.mit;
      platforms = ["aarch64-darwin"];
    };
  }
