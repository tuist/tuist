defmodule XcodeProcessorWeb.HealthController do
  use XcodeProcessorWeb, :controller

  def check(conn, _params) do
    if XcodeProcessor.XCResultNIF.nif_loaded?() do
      json(conn, %{
        status: "ok",
        version: System.get_env("DEPLOY_ENV", "dev"),
        git_sha: System.get_env("GIT_SHA", "unknown")
      })
    else
      conn
      |> put_status(503)
      |> json(%{
        status: "error",
        reason: "xcresult NIF not loaded"
      })
    end
  end
end
