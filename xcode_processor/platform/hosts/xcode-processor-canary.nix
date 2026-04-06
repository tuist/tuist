{ pkgs, ... }:

{
  networking.hostName = "xcode-processor-canary";
  networking.localHostName = "xcode-processor-canary";

  sops.defaultSopsFile = ../secrets/canary.yaml;

  environment.etc."caddy/Caddyfile".text = ''
    xcode-processor-canary.tuist.dev {
      reverse_proxy localhost:4003
    }
  '';
}
