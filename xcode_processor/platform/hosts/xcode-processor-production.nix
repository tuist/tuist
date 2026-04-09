{ pkgs, ... }:

{
  networking.hostName = "xcode-processor-production";
  networking.localHostName = "xcode-processor-production";

  sops.defaultSopsFile = ../secrets/production.yaml;

  environment.etc."caddy/Caddyfile".text = ''
    xcode-processor.tuist.dev {
      reverse_proxy localhost:4003
    }
  '';
}
