defmodule TuistWeb.API.OIDCControllerLoggingTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use Mimic

  alias Tuist.OIDC
  alias Tuist.OIDC.ScopeRules
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  test "logs withheld scopes with the resources they were withheld for", %{conn: conn} do
    project =
      ProjectsFixtures.project_fixture(
        vcs_connection: [repository_full_handle: "tuist/rules-logging"],
        preload: [:account, :vcs_connection]
      )

    {:ok, _} = ScopeRules.put_project_rule(project, "project:previews:write", %{refs: ["refs/heads/main"]})

    stub(OIDC, :claims, fn _token ->
      {:ok, %{repository: "tuist/rules-logging", provider: :github_actions, ref: "refs/heads/feature"}}
    end)

    log =
      capture_info_log(fn ->
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/auth/oidc/token", %{token: "oidc-token"})
        |> json_response(:ok)
      end)

    assert log =~ "withheld_scopes=project:previews:write=#{project.id}"
  end

  defp capture_info_log(fun) do
    previous = Logger.level()
    Logger.configure(level: :info)

    try do
      ExUnit.CaptureLog.capture_log(fun)
    after
      Logger.configure(level: previous)
    end
  end
end
