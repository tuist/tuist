{pkgs, ...}: {
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  environment.systemPackages = with pkgs; [
    bash
    coreutils
    curl
    git
    gnused
    gnutar
    gzip
    jq
    nushell
    socat
    zstd
  ];
}
