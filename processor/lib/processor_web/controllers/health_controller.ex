defmodule ProcessorWeb.HealthController do
  use ProcessorWeb, :controller

  def check(conn, _params) do
    json(conn, %{
      status: "ok",
      version: System.get_env("KAMAL_VERSION", "dev"),
      git_sha: System.get_env("GIT_SHA", "unknown")
    })
  end
end
