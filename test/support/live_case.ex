defmodule Tuist.LiveCase do
  @moduledoc ~S"""
  This module stubs some interactions with the outside world that happen from the root layouts.
  Without it, individual live view tests would need to stub it to prevent the real calls from happening.
  """
  use ExUnit.CaseTemplate

  using do
    quote do
      use Mimic
      setup :set_mimic_from_context
    end
  end

  setup do
    Tuist.GitHub.Releases |> Mimic.stub(:get_latest_cli_release, fn -> nil end)
    Tuist.GitHub.Releases |> Mimic.stub(:get_latest_app_release, fn -> nil end)
    :ok
  end
end
