{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    elixir_1_18
    erlang_27
    sops
    age
  ];
}
