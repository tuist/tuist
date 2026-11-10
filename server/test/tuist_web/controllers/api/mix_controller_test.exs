defmodule TuistWeb.API.MixControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true

  import OpenApiSpex.TestAssertions, only: [assert_schema: 3]

  alias Tuist.Accounts.AuthenticatedAccount
  alias Tuist.MCP.Components.Tools.GetMixBuild
  alias Tuist.MCP.Components.Tools.ListMixBuilds
  alias Tuist.Mix
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistWeb.API.Spec
  alias TuistWeb.Authentication

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture(preload: [:account])
    project = ProjectsFixtures.project_fixture(account_id: user.account.id, build_system: :mix)
    path = "/api/projects/#{user.account.name}/#{project.name}/mix/builds"
    %{conn: Authentication.put_current_user(conn, user), user: user, project: project, path: path}
  end

  describe "GET /api/projects/:account_handle/:project_handle/mix/builds" do
    test "lists the project's builds newest first", %{conn: conn, user: user, project: project, path: path} do
      older = build(project, user, inserted_at: ~N[2026-10-01 10:00:00])

      newer =
        build(project, user,
          elixir_version: "1.19.1",
          otp_version: "28",
          mix_env: "prod",
          is_ci: true,
          git_branch: "main",
          git_commit_sha: "abc123",
          custom_metadata: %{tags: ["nightly"], values: %{"team" => "web"}},
          diagnostics: [%{severity: "warning", file: "lib/a.ex", message: "unused variable", line: 1}]
        )

      build(ProjectsFixtures.project_fixture(account_id: user.account.id), user, [])

      response = conn |> get(path) |> json_response(200)
      assert_schema(response, "MixBuildList", Spec.spec())

      assert Enum.map(response["builds"], & &1["id"]) == [newer, older]
      [latest, _] = response["builds"]
      assert latest["elixir_version"] == "1.19.1"
      assert latest["otp_version"] == "28"
      assert latest["mix_env"] == "prod"
      assert latest["is_ci"] == true
      assert latest["git_branch"] == "main"
      assert latest["git_commit_sha"] == "abc123"
      assert latest["custom_metadata"] == %{"tags" => ["nightly"], "values" => %{"team" => "web"}}
      assert latest["diagnostics_warning_count"] == 1
      assert latest["diagnostics_error_count"] == 0
      assert latest["actor"]["name"]
      refute Map.has_key?(latest, "cache")
      assert response["pagination_metadata"]["total_count"] == 2
    end

    test "filters and paginates", %{conn: conn, user: user, project: project, path: path} do
      matching = build(project, user, status: "failure", git_branch: "feature", mix_env: "test")
      build(project, user, status: "success", git_branch: "feature", mix_env: "test")
      build(project, user, status: "failure", git_branch: "main", mix_env: "test")
      build(project, user, status: "failure", git_branch: "feature", mix_env: "dev")
      build(project, user, status: "failure", git_branch: "feature", mix_env: "test", is_ci: true)

      response =
        conn
        |> get(path <> "?status=failure&git_branch=feature&mix_env=test&is_ci=false")
        |> json_response(200)

      assert Enum.map(response["builds"], & &1["id"]) == [matching]

      page = conn |> get(path <> "?page=2&page_size=3") |> json_response(200)
      assert length(page["builds"]) == 2
      assert page["pagination_metadata"]["current_page"] == 2
      assert page["pagination_metadata"]["has_previous_page"] == true
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

    test "refuses another account's private project", %{conn: conn, project: project, path: path} do
      other = AccountsFixtures.user_fixture(preload: [:account])
      assert conn |> Authentication.put_current_user(other) |> get(path) |> json_response(:forbidden)
      assert project.visibility == :private
    end
  end

  describe "GET /api/projects/:account_handle/:project_handle/mix/builds/:build_id" do
    test "returns the build with diagnostics counts and the cache summary", %{
      conn: conn,
      user: user,
      project: project,
      path: path
    } do
      id =
        build(project, user,
          diagnostics: [
            %{severity: "error", file: "lib/a.ex", message: "undefined function", line: 1},
            %{severity: "warning", file: "lib/b.ex", message: "unused alias", line: 2}
          ],
          dependency_cache: [
            %{
              dependency: "jason",
              key: String.duplicate("a", 64),
              outcome: "local_hit",
              duration_ms: 10,
              saved_duration_ms: 500,
              read_bytes: 4_000,
              read_duration_us: 5_000,
              read_source: "local"
            },
            %{
              dependency: "decimal",
              key: String.duplicate("b", 64),
              outcome: "miss",
              duration_ms: 10,
              write_bytes: 2_000,
              write_duration_us: 20_000,
              write_source: "local"
            },
            %{dependency: "native", key: "", outcome: "bypass", duration_ms: 1, reason: "custom_compiler"}
          ]
        )

      response = conn |> get(path <> "/" <> id) |> json_response(200)
      assert_schema(response, "MixBuildDetail", Spec.spec())

      assert response["id"] == id
      assert response["diagnostics_error_count"] == 1
      assert response["diagnostics_warning_count"] == 1

      assert %{
               "hits" => 1,
               "local_hits" => 1,
               "remote_hits" => 0,
               "misses" => 1,
               "bypasses" => 1,
               "hit_rate" => 50.0,
               "saved_duration_ms" => 500,
               "read_bytes" => 4_000,
               "write_bytes" => 2_000
             } = response["cache"]
    end

    test "returns an empty cache summary for builds without observations", %{
      conn: conn,
      user: user,
      project: project,
      path: path
    } do
      id = build(project, user, [])

      assert %{"hits" => 0, "misses" => 0, "hit_rate" => nil, "saved_duration_ms" => nil, "read_bytes" => nil} =
               conn |> get(path <> "/" <> id) |> json_response(200) |> Map.fetch!("cache")
    end

    test "returns 404 for unknown and other projects' builds", %{conn: conn, user: user, path: path} do
      other = build(ProjectsFixtures.project_fixture(account_id: user.account.id), user, [])

      for id <- [UUIDv7.generate(), "not-a-uuid", other] do
        assert %{"message" => "Build not found."} = conn |> get(path <> "/" <> id) |> json_response(404)
      end
    end

    test "refuses another account's private project", %{conn: conn, user: user, project: project, path: path} do
      id = build(project, user, [])
      other = AccountsFixtures.user_fixture(preload: [:account])

      assert conn |> Authentication.put_current_user(other) |> get(path <> "/" <> id) |> json_response(:forbidden)
    end
  end

  test "the API and MCP tools return the same shapes", %{conn: conn, user: user, project: project, path: path} do
    id = build(project, user, git_branch: "main", custom_metadata: %{tags: ["nightly"], values: %{"team" => "web"}})
    args = %{"account_handle" => user.account.name, "project_handle" => project.name}
    mcp = %Plug.Conn{assigns: %{current_user: user}}

    assert %{"structuredContent" => list} = ListMixBuilds.call(mcp, args)
    assert list == conn |> get(path) |> json_response(200)

    assert %{"structuredContent" => detail} = GetMixBuild.call(mcp, Map.put(args, "build_id", id))
    assert detail == conn |> get(path <> "/" <> id) |> json_response(200)
  end

  defp build(project, user, attrs) do
    {metadata, attrs} = Keyword.pop(attrs, :custom_metadata, %{})
    id = UUIDv7.generate()

    {:ok, ^id} =
      Mix.create_build(
        Map.merge(
          %{
            id: id,
            project_id: project.id,
            account_id: user.account.id,
            duration_ms: 2_000,
            status: "success",
            custom_tags: Map.get(metadata, :tags, []),
            custom_values: Map.get(metadata, :values, %{})
          },
          Map.new(attrs)
        )
      )

    for buffer <- [Mix.Build.Buffer, Mix.Diagnostic.Buffer, Mix.CacheEvent.Buffer], do: buffer.flush()
    id
  end
end
