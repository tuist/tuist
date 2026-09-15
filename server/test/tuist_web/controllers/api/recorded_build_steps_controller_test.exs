defmodule TuistWeb.API.RecordedBuildStepsControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true

  import OpenApiSpex.TestAssertions, only: [assert_schema: 3]

  alias Tuist.Bazel
  alias Tuist.MCP.Components.Tools.GetBazelBuildStep
  alias Tuist.MCP.Components.Tools.GetGradleBuildStep
  alias Tuist.MCP.Components.Tools.ListBazelBuildSteps
  alias Tuist.MCP.Components.Tools.ListGradleBuildSteps
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.GradleFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistWeb.API.Spec
  alias TuistWeb.Authentication

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture(preload: [:account])
    project = ProjectsFixtures.project_fixture(account_id: user.account.id)
    other = ProjectsFixtures.project_fixture(account_id: user.account.id)
    start = DateTime.truncate(DateTime.utc_now(), :second)

    gradle_id =
      GradleFixtures.build_fixture(
        project_id: project.id,
        account_id: user.account.id,
        started_at: start,
        tasks: [%{task_path: ":app:compile", outcome: "remote_hit", started_at: start, duration_ms: 100}]
      )

    invocation_id = Ecto.UUID.generate()

    Bazel.create_invocations([
      %{
        project_id: project.id,
        invocation_id: invocation_id,
        account_handle: user.account.name,
        project_handle: project.name,
        command: "build",
        status: "success",
        exit_code: 0,
        started_at: DateTime.to_naive(start),
        finished_at: DateTime.to_naive(start),
        duration_ms: 500,
        target_patterns: [],
        cache_endpoint: "",
        build_timeline_span_lanes: [0],
        build_timeline_span_start_ms: [0],
        build_timeline_span_durations_ms: [100],
        build_timeline_span_categories: ["execution"],
        build_timeline_span_descriptions: ["Compile App"]
      }
    ])

    root = "/api/projects/#{user.account.name}/#{project.name}"

    %{
      conn: Authentication.put_current_user(conn, user),
      user: user,
      project: project,
      other: other,
      tools: [
        {ListGradleBuildSteps, GetGradleBuildStep, %{"build_run_id" => gradle_id}},
        {ListBazelBuildSteps, GetBazelBuildStep,
         %{"account_handle" => user.account.name, "project_handle" => project.name, "invocation_id" => invocation_id}}
      ],
      paths: [
        {root <> "/gradle/builds/#{gradle_id}/steps", "Gradle"},
        {root <> "/bazel/invocations/#{invocation_id}/steps", "Bazel"}
      ]
    }
  end

  test "lists and inspects recorded steps with explicit coverage and unavailable logs", %{conn: conn, paths: paths} do
    for {path, source} <- paths do
      result = conn |> get(path, %{page_size: 1, search: "COMPILE"}) |> json_response(200)
      assert_schema(result, source <> "BuildStepsList", Spec.spec())
      assert %{"steps" => [step], "availability" => "available", "time_origin" => "build_start"} = result
      refute Map.has_key?(step, "log")
      detail = conn |> get(path <> "/" <> step["id"]) |> json_response(200)
      assert_schema(detail, source <> "BuildStepDetail", Spec.spec())
      assert detail["log"] == nil

      assert %{"steps" => [], "availability" => "available"} =
               conn |> get(path, %{search: "missing"}) |> json_response(200)

      assert conn |> get(path, %{page_size: 101}) |> json_response(400)
      assert conn |> get(path, %{start_ms: 200, end_ms: 100}) |> json_response(400)
      assert conn |> get(path <> "/missing") |> json_response(404)
    end
  end

  test "MCP tools share the filters, opaque IDs and authorization", %{tools: tools, user: user} do
    conn = %Plug.Conn{assigns: %{current_user: user}}
    stranger = %Plug.Conn{assigns: %{current_user: AccountsFixtures.user_fixture()}}

    for {list, get, args} <- tools do
      result = list.call(conn, Map.merge(args, %{"search" => "COMPILE", "page_size" => 1}))
      refute result["isError"]
      assert %{"steps" => [step], "time_origin" => "build_start"} = decode(result)
      details = get.call(conn, Map.put(args, "step_id", step["id"]))
      refute details["isError"]
      assert %{"log" => nil} = decode(details)
      assert list.call(stranger, args)["isError"]
      assert get.call(stranger, Map.put(args, "step_id", step["id"]))["isError"]
      assert list.call(conn, Map.put(args, "page_size", 101))["isError"]
    end
  end

  defp decode(result), do: result["content"] |> hd() |> Map.fetch!("text") |> JSON.decode!()

  test "scopes both endpoints to their parent project and authorizes access", %{
    conn: conn,
    paths: paths,
    project: project,
    other: other
  } do
    stranger = Authentication.put_current_user(build_conn(), AccountsFixtures.user_fixture())

    for {path, _} <- paths do
      foreign_path = String.replace(path, "/#{project.name}/", "/#{other.name}/")
      assert conn |> get(foreign_path) |> json_response(404)
      assert conn |> get(foreign_path <> "/0") |> json_response(404)
      assert stranger |> get(path) |> json_response(403)
      assert stranger |> get(path <> "/0") |> json_response(403)
    end
  end
end
