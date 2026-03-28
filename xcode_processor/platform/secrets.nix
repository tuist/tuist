{ config, ... }:

{
  sops.defaultSopsFile = ./secrets.yaml;
  sops.age.keyFile = "/var/lib/sops-nix/key.txt";

  sops.secrets = {
    secret_key_base = {};
    webhook_secret = {};
    s3_endpoint = {};
    s3_bucket = {};
    s3_access_key_id = {};
    s3_secret_access_key = {};
    s3_region = {};
  };
}
