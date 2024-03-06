defmodule TuistCloud.Environment do
  @moduledoc false
  @env Mix.env()

  def env, do: @env

  def on_premise? do
    System.get_env("TUIST_CLOUD_SELF_HOSTED", "0") == "1"
  end
end
