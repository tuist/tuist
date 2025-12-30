defmodule TuistTestSupport.Cases.LiveCase do
  @moduledoc ~S"""
  This module stubs some interactions with the outside world that happen from the root layouts.
  Without it, individual live view tests would need to stub it to prevent the real calls from happening.
  """
  use ExUnit.CaseTemplate

  alias Tuist.GitHub.Releases

  using do
    quote do
      use Mimic

      setup :set_mimic_from_context
    end
  end

  setup do
    Mimic.stub(Releases, :get_latest_cli_release, fn -> nil end)
    Mimic.stub(Releases, :get_latest_app_release, fn -> nil end)
    :ok
  end
end
