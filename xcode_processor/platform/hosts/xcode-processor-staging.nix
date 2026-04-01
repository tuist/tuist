{ pkgs, ... }:

{
  networking.hostName = "xcode-processor-staging";
  networking.localHostName = "xcode-processor-staging";

  sops.defaultSopsFile = ../secrets/staging.yaml;

  environment.etc."caddy/Caddyfile".text = ''
    xcode-processor-staging.tuist.dev {
      reverse_proxy localhost:4003
    }
  '';
}
