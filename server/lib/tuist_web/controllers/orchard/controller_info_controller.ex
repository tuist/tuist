defmodule TuistWeb.Orchard.ControllerInfoController do
  @moduledoc """
  GET /api/orchard/v1/controller/info — workers and CLI clients hit this
  during startup to discover capabilities and versions.
  """
  use TuistWeb, :controller

  def info(conn, _params) do
    json(conn, %{
      "implementation" => "tuist-orchard-embedded",
      "version" => :tuist |> Application.spec(:vsn) |> to_string(),
      "capabilities" => [
        # No port-forward / exec yet; advertise only what we implement.
        "compute"
      ],
      "now" => DateTime.to_iso8601(DateTime.utc_now())
    })
  end
end
