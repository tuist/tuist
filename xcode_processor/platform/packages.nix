{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    elixir_1_19
    erlang_28
    sops
    age
  ];
}
