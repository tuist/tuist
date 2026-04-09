{ ... }:

{
  users.users.cschmatzler = {
    home = "/Users/cschmatzler";
    shell = "/bin/zsh";
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGOfrE2AZ6sNP6eDnbEr/DDPmBEFtIVfFtKwJXcOyxnD cschmatzler@tahani"
    ];
  };

  users.users.mfort = {
    home = "/Users/mfort";
    shell = "/bin/zsh";
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMqEhbEcT+YVhUfVVKbHiNxfdA62t1pR2y7VdCKglUEY marek@tuist.dev"
    ];
  };

  users.users.pedro = {
    home = "/Users/pedro";
    shell = "/bin/zsh";
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEaRmYaCAZj3vvaPNXq85WNjXlev6fSIJBW26WlfkD3p pedro@pepicrft.me"
    ];
  };
}
