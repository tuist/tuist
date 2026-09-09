defmodule TuistWeb.API.BuildStepsControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use Mimic

  import OpenApiSpex.TestAssertions, only: [assert_schema: 3]

  alias Tuist.FeatureFlags
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures
  alias TuistWeb.API.Spec
  alias TuistWeb.Authentication

  setup do
    stub(FeatureFlags, :build_steps_enabled?, fn _account -> true end)
    :ok
  end

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture(preload: [:account])
    project = ProjectsFixtures.project_fixture(account_id: user.account.id)

    {:ok, build} =
      RunsFixtures.build_fixture(
        project_id: project.id,
        user_id: user.account.id,
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

    path = "/api/projects/#{user.account.name}/#{project.name}/xcode/builds/#{build.id}/steps"
    %{conn: Authentication.put_current_user(conn, user), path: path, user: user, project: project}
  end

  test "lists metadata with pagination and gets logs with a precision-safe ID", %{conn: conn, path: path} do
    response = conn |> get(path, %{page_size: 1, search: "EMIT"}) |> json_response(200)
    assert_schema(response, "XcodeBuildStepsList", Spec.spec())

    assert %{
             "steps" => [step],
             "availability" => "available",
             "pagination_metadata" => %{"total_count" => 1, "page_size" => 1}
           } = response

    refute Map.has_key?(step, "log")
    assert step["id"] == "18446744073709551615"

    details = conn |> get(path <> "/" <> step["id"]) |> json_response(200)
    assert_schema(details, "XcodeBuildStepDetail", Spec.spec())

    assert %{"id" => "18446744073709551615", "log" => "EmitSwiftModule normal arm64", "log_truncated" => true} =
             details
  end

  test "rejects invalid pagination and ranges", %{conn: conn, path: path} do
    assert conn |> get(path, %{page_size: 101}) |> json_response(400)
    assert conn |> get(path, %{start_ms: 100, end_ms: 50}) |> json_response(400)
    assert conn |> get(path <> "/18446744073709551616") |> json_response(400)
    assert conn |> get(path <> "/abc") |> json_response(400)
  end

  test "returns 404 for missing steps or a build in another project", %{
    conn: conn,
    path: path,
    user: user,
    project: project
  } do
    assert conn |> get(path <> "/1") |> json_response(404)
    {:ok, other} = RunsFixtures.build_fixture()
    foreign_path = "/api/projects/#{user.account.name}/#{project.name}/xcode/builds/#{other.id}/steps"
    assert conn |> get(foreign_path) |> json_response(404)
    assert conn |> get(foreign_path <> "/18446744073709551615") |> json_response(404)
  end

  test "requires access to the project for both operations", %{path: path} do
    stranger = AccountsFixtures.user_fixture()
    conn = Authentication.put_current_user(build_conn(), stranger)
    assert conn |> get(path) |> json_response(403)
    assert conn |> get(path <> "/18446744073709551615") |> json_response(403)
  end
end
