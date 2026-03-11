{
  inputs,
  ...
}: {
  nix-homebrew = {
    enable = true;
    enableRosetta = true;
    autoMigrate = true;
    taps = {
      "homebrew/homebrew-core" = inputs.homebrew-core;
      "homebrew/homebrew-cask" = inputs.homebrew-cask;
    };
    mutableTaps = false;
  };

  homebrew = {
    enable = true;
    brews = ["aria2"];
    onActivation = {
      autoUpdate = true;
      cleanup = "none";
      upgrade = true;
    };
  };
}
