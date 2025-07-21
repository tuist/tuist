defmodule TuistWeb.AppleAppSiteAssociationController do
  use TuistWeb, :controller

  alias Tuist.Environment

  @doc """
  Serves the Apple App Site Association file dynamically based on the environment.
  """
  def show(conn, _params) do
    app_id = get_app_id()

    association = %{
      applinks: %{
        apps: [],
        details: [
          %{
            appID: app_id,
            paths: ["/*/*/previews/*"]
          }
        ]
      }
    }

    conn
    |> put_resp_content_type("application/json")
    |> json(association)
  end

  defp get_app_id do
    team_id = "U6LC622NKF"

    bundle_id =
      cond do
        Environment.staging?() -> "dev.tuist.app.staging"
        Environment.canary?() -> "dev.tuist.app.canary"
        true -> "dev.tuist.app"
      end

    "#{team_id}.#{bundle_id}"
  end
end
