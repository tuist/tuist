defmodule TuistWeb.API.CargoControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true

  import OpenApiSpex.TestAssertions, only: [assert_schema: 3]

  alias Tuist.Accounts.AuthenticatedAccount
  alias Tuist.Cargo
  alias Tuist.MCP.Components.Tools.GetCargoBuild
  alias Tuist.MCP.Components.Tools.ListCargoBuilds
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistWeb.API.Spec
  alias TuistWeb.Authentication

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture(preload: [:account])
    project = ProjectsFixtures.project_fixture(account_id: user.account.id, build_system: :cargo)
    path = "/api/projects/#{user.account.name}/#{project.name}/cargo/builds"
    %{conn: Authentication.put_current_user(conn, user), user: user, project: project, path: path}
  end

  describe "GET /api/projects/:account_handle/:project_handle/cargo/builds" do
    test "lists the project's builds without nextest runs", %{
      conn: conn,
      user: user,
      project: project,
      path: path
    } do
      check = build(project, user, command: "check")

      id =
        build(project, user,
          command: "build",
          git_branch: "main",
          git_commit_sha: "abc123",
          is_ci: true,
          ci_provider: "github",
          started_at: "2026-10-02T10:00:00Z"
        )

      build(project, user, command: "nextest")
      build(ProjectsFixtures.project_fixture(account_id: user.account.id), user, command: "build")

      response = conn |> get(path) |> json_response(200)
      assert_schema(response, "CargoBuildList", Spec.spec())

      assert response["builds"] |> Enum.map(& &1["id"]) |> Enum.sort() == Enum.sort([id, check])
      latest = Enum.find(response["builds"], &(&1["id"] == id))
      assert latest["command"] == "build"
      assert latest["rust_version"] == "rustc 1.97.1"
      assert latest["status"] == "success"
      assert latest["duration_ms"] == 2000
      assert latest["is_ci"] == true
      assert latest["git_branch"] == "main"
      assert latest["git_commit_sha"] == "abc123"
      assert latest["git_ref"] == nil
      assert latest["ci_provider"] == "github"
      assert latest["started_at"] == "2026-10-02T10:00:00Z"
      assert latest["actor"]["name"] == user.account.name
      refute Map.has_key?(latest, "cache")
      refute Map.has_key?(latest, "compilations")

      assert response["pagination_metadata"] == %{
               "has_next_page" => false,
               "has_previous_page" => false,
               "current_page" => 1,
               "page_size" => 20,
               "total_count" => 2,
               "total_pages" => 1
             }
    end

    test "filters and paginates", %{conn: conn, user: user, project: project, path: path} do
      failed = build(project, user, status: "failure", git_branch: "feature", command: "check", is_ci: false)
      build(project, user, status: "success", git_branch: "feature", command: "check")
      build(project, user, status: "failure", git_branch: "main", command: "check")
      build(project, user, status: "failure", git_branch: "feature", command: "build")

      response =
        conn
        |> get(path <> "?status=failure&git_branch=feature&command=check&is_ci=false")
        |> json_response(200)

      assert Enum.map(response["builds"], & &1["id"]) == [failed]

      page = conn |> get(path <> "?page=2&page_size=3") |> json_response(200)
      assert length(page["builds"]) == 1
      assert page["pagination_metadata"]["has_previous_page"] == true
      assert page["pagination_metadata"]["total_count"] == 4
    end

    test "rejects page sizes over 100", %{conn: conn, path: path} do
      assert conn |> get(path <> "?page_size=101") |> json_response(400)
    end

    test "allows an account token with project:builds:read", %{conn: conn, user: user, project: project, path: path} do
      id = build(project, user, [])

      response =
        conn
        |> assign(:current_subject, %AuthenticatedAccount{
          account: user.account,
          scopes: ["project:builds:read"],
          all_projects: false,
          project_ids: [project.id]
        })
        |> get(path)
        |> json_response(200)

      assert Enum.map(response["builds"], & &1["id"]) == [id]
    end

    test "refuses another account's private project", %{conn: conn, project: project} do
      build(project, %{account: %{id: project.account_id}}, [])
      other = AccountsFixtures.user_fixture(preload: [:account])

      conn =
        conn
        |> Authentication.put_current_user(other)
        |> get("/api/projects/#{project.account.name}/#{project.name}/cargo/builds")

      assert json_response(conn, :forbidden)
    end
  end

  describe "GET /api/projects/:account_handle/:project_handle/cargo/builds/:build_id" do
    test "returns the build with decoded cache counters and no raw inspection", %{
      conn: conn,
      user: user,
      project: project,
      path: path
    } do
      details = %{
        version: 1,
        truncated: false,
        tasks: [
          %{
            key: "blake3:#{String.duplicate("a", 64)}:123",
            name: "private-task-name",
            kind: "rust",
            status: "hit",
            cas_keys: []
          }
        ],
        cas_outputs: []
      }

      id =
        build(project, user,
          cache: %{version: 1, hits: 12, misses: 2, unconsulted: 3, downloaded_bytes: 4096, details: details}
        )

      response = conn |> get(path <> "/" <> id) |> json_response(200)
      assert_schema(response, "CargoBuildDetail", Spec.spec())

      assert response["id"] == id
      assert response["cache"]["hits"] == 12
      assert response["cache"]["misses"] == 2
      assert response["cache"]["unconsulted"] == 3
      assert response["cache"]["task_misses"] == 5
      assert response["cache"]["hit_rate"] == 70.6
      assert response["cache"]["downloaded_bytes"] == 4096
      refute Map.has_key?(response["cache"], "details")
      refute JSON.encode!(response) =~ "private-task-name"

      inspected = conn |> get(path <> "/" <> id <> "?include_cache_inspection=true") |> json_response(200)
      assert_schema(inspected, "CargoBuildDetail", Spec.spec())
      assert inspected["cache_inspection"] == JSON.decode!(JSON.encode!(details))

      args = %{
        "account_handle" => user.account.name,
        "project_handle" => project.name,
        "build_id" => id,
        "include_cache_inspection" => true
      }

      assert %{"structuredContent" => ^inspected} =
               GetCargoBuild.call(%Plug.Conn{assigns: %{current_user: user}}, args)
    end

    test "returns a null cache for builds without measurements", %{conn: conn, user: user, project: project, path: path} do
      id = build(project, user, [])

      assert %{"cache" => nil, "cache_inspection" => nil} =
               conn |> get(path <> "/" <> id <> "?include_cache_inspection=true") |> json_response(200)
    end

    test "returns 404 for unknown, malformed and other projects' builds", %{
      conn: conn,
      user: user,
      project: project,
      path: path
    } do
      other = build(ProjectsFixtures.project_fixture(account_id: user.account.id), user, [])
      build(project, user, [])

      for id <- [Ecto.UUID.generate(), "not-a-uuid", other] do
        assert %{"message" => "Build not found."} = conn |> get(path <> "/" <> id) |> json_response(404)
      end
    end

    test "refuses another account's private project", %{conn: conn, project: project} do
      id = build(project, %{account: %{id: project.account_id}}, [])
      other = AccountsFixtures.user_fixture(preload: [:account])

      conn =
        conn
        |> Authentication.put_current_user(other)
        |> get("/api/projects/#{project.account.name}/#{project.name}/cargo/builds/#{id}")

      assert json_response(conn, :forbidden)
    end
  end

  test "the API and MCP tools return the same shapes", %{conn: conn, user: user, project: project, path: path} do
    values = Map.new(1..64, &{"future.#{&1}", "unicode ✓ #{&1}"})

    id =
      build(project, user,
        cache: %{version: 1, hits: 1, misses: 1},
        git_branch: "main",
        custom_metadata: %{tags: ["ci"], values: values},
        compilations: [
          %{
            name: "widgets",
            source: "src/lib.rs",
            kind: "lib",
            dependencies: ["serde"],
            start_offset_ms: 0,
            duration_ms: 0,
            status: "failure",
            diagnostics: [
              %{severity: "error", message: "type mismatch <script>", file: "src/lib.rs", line: 7},
              %{severity: "warning", message: "unused", file: nil, line: nil}
            ]
          }
        ]
      )

    sibling = ProjectsFixtures.project_fixture(account_id: user.account.id)
    build(sibling, user, id: id, compilations: [compilation("private-sibling", 0)])

    args = %{"account_handle" => user.account.name, "project_handle" => project.name}
    mcp = %Plug.Conn{assigns: %{current_user: user}}

    assert %{"structuredContent" => list} = ListCargoBuilds.call(mcp, args)
    assert list == conn |> get(path) |> json_response(200)

    assert %{"structuredContent" => detail} = GetCargoBuild.call(mcp, Map.put(args, "build_id", id))
    assert detail == conn |> get(path <> "/" <> id) |> json_response(200)
    assert detail["custom_metadata"] == %{"tags" => ["ci"], "values" => values}
    assert detail["compilations_truncated"] == false
    assert [compilation] = detail["compilations"]
    assert compilation["name"] == "widgets"
    assert compilation["source"] == "src/lib.rs"
    assert compilation["kind"] == "lib"
    assert compilation["dependencies"] == ["serde"]
    assert compilation["start_offset_ms"] == 0
    assert compilation["duration_ms"] == 0
    assert compilation["status"] == "failure"

    assert compilation["diagnostics"] == [
             %{"severity" => "error", "message" => "type mismatch <script>", "file" => "src/lib.rs", "line" => 7},
             %{"severity" => "warning", "message" => "unused", "file" => nil, "line" => nil}
           ]

    assert_schema(detail, "CargoBuildDetail", Spec.spec())
    refute JSON.encode!(detail) =~ "private-sibling"
  end

  test "detail bounds compilations with truthful truncation and start ordering", %{
    conn: conn,
    user: user,
    project: project,
    path: path
  } do
    for count <- [0, 500, 501] do
      rows = if count == 0, do: [], else: Enum.map(count..1//-1, &compilation("crate-#{&1}", &1))
      id = build(project, user, compilations: rows)
      response = conn |> get(path <> "/" <> id) |> json_response(200)
      assert length(response["compilations"]) == min(count, 500)
      assert response["compilations_truncated"] == count > 500

      assert Enum.map(response["compilations"], & &1["start_offset_ms"]) ==
               Enum.sort(Enum.map(Enum.take(Enum.reverse(rows), 500), & &1.start_offset_ms))
    end
  end

  defp compilation(name, offset) do
    %{
      name: name,
      source: "src/lib.rs",
      kind: "lib",
      dependencies: [],
      start_offset_ms: offset,
      duration_ms: 1,
      status: "success"
    }
  end

  defp build(project, user, attrs) do
    {:ok, id} =
      Cargo.create_build(
        Map.merge(
          %{
            id: UUIDv7.generate(),
            project_id: project.id,
            account_id: user.account.id,
            status: "success",
            command: "build",
            rust_version: "rustc 1.97.1",
            duration_ms: 2000
          },
          Map.new(attrs)
        )
      )

    Cargo.Build.Buffer.flush()
    Cargo.Compilation.Buffer.flush()

    id
  end
end
