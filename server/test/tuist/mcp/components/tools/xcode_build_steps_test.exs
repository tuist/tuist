defmodule Tuist.MCP.Components.Tools.XcodeBuildStepsTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.Authorization
  alias Tuist.Builds
  alias Tuist.MCP.Components.Tools.GetXcodeBuildStep
  alias Tuist.MCP.Components.Tools.ListXcodeBuildSteps
  alias Tuist.Projects
  alias TuistTestSupport.Fixtures.RunsFixtures

  setup do
    {:ok, build} =
      RunsFixtures.build_fixture(
        build_steps: [
          %{
            event_id: 18_446_744_073_709_551_615,
            title: "Emit Swift module",
            target: "App",
            project: "Workspace",
            category: "swiftCompilation",
            start_ms: 0.0,
            duration_ms: 100.0,
            status: "success",
            log: "EmitSwiftModule normal arm64",
            log_truncated: true
          }
        ]
      )

    project = %{id: build.project_id, name: "app", account: %{name: "acme"}}
    stub(Projects, :get_project_by_id, fn id when id == build.project_id -> project end)
    stub(Authorization, :authorize, fn :build_read, :subject, ^project -> :ok end)
    %{conn: %Plug.Conn{assigns: %{current_subject: :subject}}, build: build, project: project}
  end

  test "lists metadata and fetches a log using the returned string ID", %{conn: conn, build: build} do
    url = "https://tuist.dev/acme/app/builds/build-runs/#{build.id}?tab=timeline"
    result = ListXcodeBuildSteps.call(conn, %{"build_run_id" => url, "search" => "EMIT", "page_size" => 1})
    refute result["isError"]

    assert %{"steps" => [step], "availability" => "available", "pagination_metadata" => %{"page_size" => 1}} =
             decode(result)

    assert step["id"] == "18446744073709551615"
    refute Map.has_key?(step, "log")
    result = GetXcodeBuildStep.call(conn, %{"build_run_id" => build.id, "step_id" => step["id"]})
    refute result["isError"]

    assert %{"id" => "18446744073709551615", "log" => "EmitSwiftModule normal arm64", "log_truncated" => true} =
             decode(result)
  end

  test "both tools enforce build-read authorization before reading steps", %{conn: conn, build: build, project: project} do
    stub(Authorization, :authorize, fn :build_read, :subject, ^project -> {:error, :forbidden} end)

    for {tool, args} <- [
          {ListXcodeBuildSteps, %{"build_run_id" => build.id}},
          {GetXcodeBuildStep, %{"build_run_id" => build.id, "step_id" => "18446744073709551615"}}
        ] do
      result = tool.call(conn, args)
      assert result["isError"]
      assert hd(result["content"])["text"] =~ "do not have access"
    end
  end

  test "validates arguments before looking up a build", %{conn: conn} do
    reject(&Builds.get_build/1)

    for {tool, args} <- [
          {ListXcodeBuildSteps, %{"build_run_id" => "unused", "page_size" => 101}},
          {GetXcodeBuildStep, %{"build_run_id" => "unused", "step_id" => 1}},
          {GetXcodeBuildStep, %{"build_run_id" => "unused", "step_id" => "+1"}}
        ] do
      assert tool.call(conn, args)["isError"]
    end
  end

  test "reports invalid ranges and missing or out-of-range steps", %{conn: conn, build: build} do
    assert ListXcodeBuildSteps.call(conn, %{"build_run_id" => build.id, "start_ms" => 10, "end_ms" => 5})["isError"]
    assert GetXcodeBuildStep.call(conn, %{"build_run_id" => build.id, "step_id" => "18446744073709551616"})["isError"]
    result = GetXcodeBuildStep.call(conn, %{"build_run_id" => build.id, "step_id" => "1"})
    assert result["isError"]
    assert hd(result["content"])["text"] == "Build step not found."
    assert ListXcodeBuildSteps.call(conn, %{"build_run_id" => Ecto.UUID.generate()})["isError"]
  end

  defp decode(%{"content" => [%{"type" => "text", "text" => text}]}), do: JSON.decode!(text)
end
