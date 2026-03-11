{ 
  lib,
  pkgs,
  ...
}: let
  xcodeVersion = lib.removeSuffix "\n" (builtins.readFile ../xcode-version);
in {
  services.github-runners.tuist = {
    enable = lib.mkDefault false;
    url = lib.mkDefault "https://github.com/tuist";
    name = lib.mkDefault "tuist-m1-runner-par-01";
    package = pkgs.callPackage ../pkgs/github-runner-binary.nix {};
    tokenFile = lib.mkDefault "/var/run/tuist/github-runner.token";
    replace = true;
    extraLabels = [
      "tuist"
      "macos"
      "apple-silicon"
      "scaleway"
      "m1"
      "xcode-${lib.replaceStrings ["."] ["-"] xcodeVersion}"
    ];
    extraPackages = with pkgs; [
      bash
      coreutils
      curl
      git
      gnused
      gnutar
      gzip
      jq
      zstd
    ];
    serviceOverrides = {
      SessionCreate = true;
    };
  };
}
