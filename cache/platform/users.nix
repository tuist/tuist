{
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIL/I+/2QT47raegzMIyhwMEPKarJP/+Ox9ewA4ZFJwk/ cschmatzler@tahani"
  ];

  users.users.cschmatzler = {
    isNormalUser = true;
    extraGroups = ["wheel" "docker"];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIL/I+/2QT47raegzMIyhwMEPKarJP/+Ox9ewA4ZFJwk/ cschmatzler@tahani"
    ];
  };

  users.users.mfort = {
    isNormalUser = true;
    extraGroups = ["wheel" "docker"];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIB/Y8pQ/HHZ1BKE+DILq/gE7cd8tSiGHcT8pj5wR2f4W marek@tuist.dev"
    ];
  };

  users.users.github-actions = {
    isNormalUser = true;
    extraGroups = ["docker"];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAII0j+FOf7IUXTuH8oMXRCxsnqhvAek+HT7gSF8mRIf5q github-actions@github"
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
