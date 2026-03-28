{ pkgs, ... }:

{
  networking.hostName = "xcode-processor-paris-1";
  networking.localHostName = "xcode-processor-paris-1";

  environment.etc."caddy/Caddyfile".text = ''
    xcode-processor-staging.tuist.dev {
      reverse_proxy localhost:4003
    }
  '';
}
