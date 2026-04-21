{
  users.users.root.openssh.authorizedKeys.keys = [];

  users.users.mfort = {
    isNormalUser = true;
    extraGroups = ["wheel" "docker"];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIB/Y8pQ/HHZ1BKE+DILq/gE7cd8tSiGHcT8pj5wR2f4W marek@tuist.dev"
    ];
  };

  users.users.pedro = {
    isNormalUser = true;
    extraGroups = ["wheel" "docker"];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKqGgvTCOAILQD/O1/yTh9K4pfTBFE+rUsPYshv1iuJU pedro@pepicrft.me"
    ];
  };

  users.users.github-actions = {
    isNormalUser = true;
    extraGroups = ["docker"];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINgLDEi6wrjfrynGCNo0vzhVtZupjHkso5O0Uh4ke+At github-actions@cache-ci"
    ];
  };

  users.users.cache = {
    isSystemUser = true;
    group = "cache";
    uid = 990;
  };

  users.groups.cache = {
    gid = 990;
  };
}
