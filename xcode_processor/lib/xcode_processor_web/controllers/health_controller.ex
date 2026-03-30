defmodule XcodeProcessorWeb.HealthController do
  use XcodeProcessorWeb, :controller

  def check(conn, _params) do
    json(conn, %{
      status: "ok",
      version: System.get_env("DEPLOY_ENV", "dev"),
      git_sha: System.get_env("GIT_SHA", "unknown")
    })
  end
end
