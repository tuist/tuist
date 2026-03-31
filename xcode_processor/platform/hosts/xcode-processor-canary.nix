{ pkgs, ... }:

{
  networking.hostName = "xcode-processor-canary";
  networking.localHostName = "xcode-processor-canary";

  environment.etc."caddy/Caddyfile".text = ''
    xcode-processor-canary.tuist.dev {
      reverse_proxy localhost:4003
    }
  '';
}
