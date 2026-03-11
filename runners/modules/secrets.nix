{
  config,
  lib,
  ...
}: let
  cfg = config.tuist.runner.secrets;
in {
  options.tuist.runner.secrets = {
    enable = lib.mkEnableOption "sops-managed runner secrets";

    defaultSopsFile = lib.mkOption {
      type = with lib.types; nullOr path;
      default = null;
      description = "SOPS file containing runner host secrets.";
    };

    xcodesEnvKey = lib.mkOption {
      type = lib.types.str;
      default = "xcodes-env";
      description = "Key inside the SOPS file for Xcode installer environment variables.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.defaultSopsFile != null;
        message = "`tuist.runner.secrets.defaultSopsFile` must be set when runner secrets are enabled.";
      }
    ];

    system.activationScripts.extraActivation.text = ''
      mkdir -p /etc/tuist
      chmod 0755 /etc/tuist
    '';

    sops = {
      defaultSopsFile = cfg.defaultSopsFile;
      age.sshKeyPaths = ["/etc/ssh/ssh_host_ed25519_key"];

      secrets.xcodes-env = {
        key = cfg.xcodesEnvKey;
        path = "/etc/tuist/xcodes.env";
        mode = "0400";
      };
    };
  };
}
