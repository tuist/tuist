{ pkgs, ... }:

{
  networking.hostName = "xcode-processor-production";
  networking.localHostName = "xcode-processor-production";

  environment.etc."caddy/Caddyfile".text = ''
    xcode-processor.tuist.dev {
      reverse_proxy localhost:4003
    }
  '';
}
