defmodule Tuist.MCP.Components.Tools.CargoBuildToolsTest do
  use TuistTestSupport.Cases.ConnCase, async: true

  alias Tuist.Accounts.AuthenticatedAccount
  alias Tuist.Cargo
  alias Tuist.MCP.Components.Tools.GetCargoBuild
  alias Tuist.MCP.Components.Tools.ListCargoBuilds
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  setup do
    user = AccountsFixtures.user_fixture(preload: [:account])
    project = ProjectsFixtures.project_fixture(account_id: user.account.id, build_system: :cargo)
    args = %{"account_handle" => user.account.name, "project_handle" => project.name}
    %{conn: %Plug.Conn{assigns: %{current_user: user}}, user: user, project: project, args: args}
  end

  test "private builds require the project's build-read access", %{user: user, project: project, args: args} do
    id = build(project, rust_version: "private-rust-secret")
    other_user = AccountsFixtures.user_fixture(preload: [:account])
    sibling = ProjectsFixtures.project_fixture(account_id: user.account.id)

    for assigns <- [
          %{},
          %{current_user: other_user},
          %{current_project: sibling},
          %{
            current_subject: %AuthenticatedAccount{
              account: user.account,
              scopes: ["project:tests:read"],
              all_projects: true
            }
          },
          %{
            current_subject: %AuthenticatedAccount{
              account: user.account,
              scopes: ["project:builds:read"],
              all_projects: false,
              project_ids: [sibling.id]
            }
          },
          %{
            current_subject: %AuthenticatedAccount{
              account: other_user.account,
              scopes: ["project:builds:read"],
              all_projects: true
            }
          }
        ],
        {tool, tool_args} <- [{ListCargoBuilds, args}, {GetCargoBuild, Map.put(args, "build_id", id)}] do
      assert %{"isError" => true, "content" => [%{"text" => text}]} =
               tool.call(%Plug.Conn{assigns: assigns}, tool_args)

      refute text =~ "private-rust-secret"
    end

    token = %AuthenticatedAccount{
      account: user.account,
      scopes: ["project:builds:read"],
      all_projects: false,
      project_ids: [project.id]
    }

    assert %{"structuredContent" => %{"rust_version" => "private-rust-secret"}} =
             GetCargoBuild.call(%Plug.Conn{assigns: %{current_subject: token}}, Map.put(args, "build_id", id))
  end

  test "a build ID reused by another project resolves within the requested project only", %{
    conn: conn,
    user: user,
    project: project,
    args: args
  } do
    id = build(project, rust_version: "victim-build")
    public = ProjectsFixtures.project_fixture(visibility: :public, build_system: :cargo)
    build(public, id: id, rust_version: "attacker-build")

    assert %{"structuredContent" => %{"rust_version" => "victim-build"}} =
             GetCargoBuild.call(conn, Map.put(args, "build_id", id))

    other = ProjectsFixtures.project_fixture(account_id: user.account.id)

    assert %{"isError" => true, "content" => [%{"text" => text}]} =
             GetCargoBuild.call(conn, %{
               "account_handle" => user.account.name,
               "project_handle" => other.name,
               "build_id" => id
             })

    assert text =~ "not found"
  end

  test "list_cargo_builds filters and paginates", %{conn: conn, project: project, args: args} do
    matching = build(project, status: "failure", command: "check", git_branch: "feature")
    build(project, status: "success", command: "check", git_branch: "feature")
    build(project, command: "nextest")

    assert %{"structuredContent" => %{"builds" => [%{"id" => ^matching}]}} =
             ListCargoBuilds.call(
               conn,
               Map.merge(args, %{"status" => "failure", "command" => "check", "git_branch" => "feature"})
             )

    assert %{"structuredContent" => %{"builds" => [_], "pagination_metadata" => %{"total_count" => 2}}} =
             ListCargoBuilds.call(conn, Map.merge(args, %{"page" => 2, "page_size" => 1}))
  end

  test "get_cargo_build exposes decoded cache counters", %{conn: conn, project: project, args: args} do
    id = build(project, cache: %{version: 1, hits: 3, misses: 1})

    assert %{"structuredContent" => %{"cache" => %{"hits" => 3, "task_misses" => 1, "hit_rate" => 75.0}}} =
             GetCargoBuild.call(conn, Map.put(args, "build_id", id))
  end

  defp build(project, attrs) do
    {:ok, id} =
      Cargo.create_build(
        Map.merge(
          %{
            id: UUIDv7.generate(),
            project_id: project.id,
            account_id: project.account_id,
            status: "success",
            command: "build",
            rust_version: "rustc 1.97.1",
            duration_ms: 2000
          },
          Map.new(attrs)
        )
      )

    Cargo.Build.Buffer.flush()
    id
  end
end
