defmodule Tuist.MCP.Components.Tools.GetBuildTraceTest do
  use TuistTestSupport.Cases.ConnCase, async: true

  alias Tuist.Builds.Trace
  alias Tuist.MCP.Components.Tools.GetBuildTrace
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures

  setup do
    user = AccountsFixtures.user_fixture(preload: [:account])
    project = ProjectsFixtures.project_fixture(account_id: user.account.id)
    {:ok, build} = RunsFixtures.build_fixture(project_id: project.id)
    %{user: user, project: project, build: build}
  end

  test "returns a link signed for the build referenced by its dashboard URL", %{
    user: user,
    project: project,
    build: build
  } do
    result =
      GetBuildTrace.call(%Plug.Conn{assigns: %{current_subject: user}}, %{
        "account_handle" => user.account.name,
        "project_handle" => project.name,
        "build_id" => "https://tuist.dev/#{user.account.name}/#{project.name}/builds/build-runs/#{build.id}"
      })

    assert %{"trace_url" => trace_url, "build_system" => "xcode"} = result["structuredContent"]
    assert "/build-traces/" <> token = URI.parse(trace_url).path
    assert Trace.verify_token(token) == {:ok, project.id, build.id}
  end

  test "does not sign links for builds of other projects or for unauthorized callers", %{
    user: user,
    project: project,
    build: build
  } do
    {:ok, other_build} = RunsFixtures.build_fixture()

    for {subject, build_id} <- [{user, other_build.id}, {AccountsFixtures.user_fixture(), build.id}] do
      result =
        GetBuildTrace.call(%Plug.Conn{assigns: %{current_subject: subject}}, %{
          "account_handle" => user.account.name,
          "project_handle" => project.name,
          "build_id" => build_id
        })

      assert result["isError"]
      refute inspect(result) =~ "build-traces"
    end
  end
end
