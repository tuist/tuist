defmodule TuistWeb.API.BuildIntegrationVersionsTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  import Ecto.Query

  alias Tuist.Builds.Build
  alias Tuist.Builds.Workers.ProcessBuildWorker
  alias Tuist.ClickHouseRepo
  alias Tuist.MCP.Components.Tools
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.CommandEventsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures
  alias TuistWeb.Authentication

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture(preload: [:account])
    stub(Tuist.VCS, :enqueue_vcs_pull_request_comment, fn _ -> :ok end)

    conn = conn |> Authentication.put_current_user(user) |> put_req_header("content-type", "application/json")
    %{conn: conn, user: user}
  end

  for {system, header, schema, list, get} <- [
        {:xcode, "x-tuist-cli-version", Build, Tools.ListXcodeBuilds, Tools.GetXcodeBuild},
        {:gradle, "x-tuist-gradle-plugin-version", Tuist.Gradle.Build, Tools.ListGradleBuilds, Tools.GetGradleBuild},
        {:mix, "x-tuist-ex-version", Tuist.Mix.Build, Tools.ListMixBuilds, Tools.GetMixBuild},
        {:cargo, "x-tuist-cli-version", Tuist.Cargo.Build, Tools.ListCargoBuilds, Tools.GetCargoBuild}
      ] do
    @system system
    @header header
    @schema schema
    @list list
    @get get

    test "#{system} accepts legacy reports and records only its own integration version", %{conn: conn, user: user} do
      project = ProjectsFixtures.project_fixture(account_id: user.account.id, build_system: @system)
      path = "/api/projects/#{user.account.name}/#{project.name}/#{@system}/builds"

      for version <- [nil, "1.2.3-canary.7+revision", "future-release/2027"] do
        request = put_req_header(conn, "x-tuist-cli-version", "99.0.0")
        request = delete_req_header(request, @header)
        request = if version, do: put_req_header(request, @header, version), else: request

        body = %{id: UUIDv7.generate(), status: "success", is_ci: false}
        body = if @system == :xcode, do: Map.put(body, :duration, 17), else: Map.put(body, :duration_ms, 17)
        body = if @system == :gradle, do: Map.put(body, :tasks, []), else: body

        response = post(request, path, body)
        %{"id" => id} = json_response(response, if(@system == :xcode, do: 200, else: 201))
        build = ClickHouseRepo.one!(from(b in @schema, where: b.project_id == ^project.id and b.id == ^id))
        assert build.tuist_version == (version || "")

        assert json_response(get(conn, path <> "/" <> id), 200)["tuist_version"] == version
        builds = json_response(get(conn, path), 200)["builds"]
        assert Enum.find(builds, &(&1["id"] == id))["tuist_version"] == version

        args = %{"account_handle" => user.account.name, "project_handle" => project.name}
        key = if @system in [:xcode, :gradle], do: "build_run_id", else: "build_id"
        assert %{"structuredContent" => detail} = @get.call(conn, Map.put(args, key, id))
        assert detail["tuist_version"] == version
        assert %{"structuredContent" => %{"builds" => builds}} = @list.call(conn, args)
        assert Enum.find(builds, &(&1["id"] == id))["tuist_version"] == version
      end
    end
  end

  test "Xcode REST and MCP distinguish the generator from the reporter without crossing projects", %{
    conn: conn,
    user: user
  } do
    project = ProjectsFixtures.project_fixture(account_id: user.account.id)
    other_project = ProjectsFixtures.project_fixture()
    generation = CommandEventsFixtures.command_event_fixture(project_id: project.id, tuist_version: "4.100.0")
    foreign = CommandEventsFixtures.command_event_fixture(project_id: other_project.id, tuist_version: "foreign-secret")

    non_generation =
      CommandEventsFixtures.command_event_fixture(project_id: project.id, name: "build", tuist_version: "not-a-generator")

    # An attacker may reuse the client's generation UUID in another project.
    CommandEventsFixtures.command_event_fixture(
      id: generation.id,
      project_id: other_project.id,
      tuist_version: "collision-secret"
    )

    args = %{"account_handle" => user.account.name, "project_handle" => project.name}
    path = "/api/projects/#{user.account.name}/#{project.name}/xcode/builds"

    for {generation_id, expected} <- [
          {generation.id, "4.100.0"},
          {foreign.id, nil},
          {non_generation.id, nil},
          {UUIDv7.generate(), nil},
          {nil, nil}
        ] do
      {:ok, build} =
        RunsFixtures.build_fixture(project_id: project.id, generation_id: generation_id, tuist_version: "4.200.0")

      assert json_response(get(conn, path <> "/" <> build.id), 200)["tuist_generation_version"] == expected
      assert %{"structuredContent" => detail} = Tools.GetXcodeBuild.call(conn, %{"build_run_id" => build.id})
      assert detail["tuist_version"] == "4.200.0"
      assert detail["tuist_generation_version"] == expected

      assert %{"structuredContent" => %{"builds" => mcp_builds}} = Tools.ListXcodeBuilds.call(conn, args)
      rest_builds = json_response(get(conn, path), 200)["builds"]

      for builds <- [rest_builds, mcp_builds] do
        result = Enum.find(builds, &(&1["id"] == build.id))
        assert result["tuist_version"] == "4.200.0"
        assert result["tuist_generation_version"] == expected
      end
    end
  end

  test "Xcode processing retains the original reporting version in its row and recovery metadata", %{
    conn: conn,
    user: user
  } do
    project = ProjectsFixtures.project_fixture(account_id: user.account.id)
    id = UUIDv7.generate()

    response =
      conn
      |> put_req_header("x-tuist-cli-version", "4.200.0-canary.2")
      |> post("/api/projects/#{user.account.name}/#{project.name}/xcode/builds", %{
        id: id,
        status: "processing",
        is_ci: false
      })

    assert %{"id" => ^id} = json_response(response, 200)

    assert ClickHouseRepo.one!(from(b in Build, where: b.project_id == ^project.id and b.id == ^id)).tuist_version ==
             "4.200.0-canary.2"

    assert [%{args: %{"build_metadata" => %{"tuist_version" => "4.200.0-canary.2"}}}] =
             all_enqueued(worker: ProcessBuildWorker)
  end
end
