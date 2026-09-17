defmodule Atlas.Environment do
  @moduledoc """
  Runtime access to the environment Atlas is running in.

  Exists so code paths that should behave differently in development than in
  production can branch on a function rather than on `Mix.env/0`, which is not
  available in a release.
  """

  def env, do: Application.get_env(:atlas, :env, :prod)

  def dev?, do: env() == :dev

  def test?, do: env() == :test

  def prod?, do: env() == :prod
end
