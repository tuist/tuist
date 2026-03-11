{
  nixpkgs.hostPlatform = "aarch64-darwin";
  nix.enable = false;

  nix-homebrew.user = "m1";

  networking.hostName = "tuist-m1-runner-par-01";
  networking.computerName = "tuist-m1-runner-par-01";
  networking.localHostName = "tuist-m1-runner-par-01";

  system.primaryUser = "m1";
  system.stateVersion = 6;

  tuist.runner.secrets = {
    enable = true;
    defaultSopsFile = ../../secrets/scaleway-m1-01.sops.yaml;
  };

  tuist.runner.vmCacheRelay.enable = true;

  services.github-runners.tuist = {
    enable = false;
    tokenFile = "/var/run/tuist/github-runner.token";
  };
}
