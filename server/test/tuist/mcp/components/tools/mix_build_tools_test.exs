defmodule Tuist.MCP.Components.Tools.MixBuildToolsTest do
  use TuistTestSupport.Cases.ConnCase, async: true

  alias Tuist.Accounts.AuthenticatedAccount
  alias Tuist.MCP.Components.Tools.GetMixBuild
  alias Tuist.MCP.Components.Tools.ListMixBuilds
  alias Tuist.Mix
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  setup do
    user = AccountsFixtures.user_fixture(preload: [:account])
    project = ProjectsFixtures.project_fixture(account_id: user.account.id, build_system: :mix)
    args = %{"account_handle" => user.account.name, "project_handle" => project.name}
    %{conn: %Plug.Conn{assigns: %{current_user: user}}, user: user, project: project, args: args}
  end

  test "private builds require the project's build-read access", %{user: user, project: project, args: args} do
    id = build(project, elixir_version: "private-elixir-secret")
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
        {tool, tool_args} <- [{ListMixBuilds, args}, {GetMixBuild, Map.put(args, "build_id", id)}] do
      assert %{"isError" => true, "content" => [%{"text" => text}]} =
               tool.call(%Plug.Conn{assigns: assigns}, tool_args)

      refute text =~ "private-elixir-secret"
    end

    token = %AuthenticatedAccount{
      account: user.account,
      scopes: ["project:builds:read"],
      all_projects: false,
      project_ids: [project.id]
    }

    assert %{"structuredContent" => %{"elixir_version" => "private-elixir-secret"}} =
             GetMixBuild.call(%Plug.Conn{assigns: %{current_subject: token}}, Map.put(args, "build_id", id))
  end

  test "a build ID reused by another project resolves within the requested project only", %{
    conn: conn,
    user: user,
    project: project,
    args: args
  } do
    id = build(project, elixir_version: "victim-build")
    public = ProjectsFixtures.project_fixture(visibility: :public, build_system: :mix)
    build(public, id: id, elixir_version: "attacker-build")

    assert %{"structuredContent" => %{"elixir_version" => "victim-build"}} =
             GetMixBuild.call(conn, Map.put(args, "build_id", id))

    other = ProjectsFixtures.project_fixture(account_id: user.account.id)

    assert %{"isError" => true, "content" => [%{"text" => text}]} =
             GetMixBuild.call(conn, %{
               "account_handle" => user.account.name,
               "project_handle" => other.name,
               "build_id" => id
             })

    assert text =~ "not found"
  end

  test "list_mix_builds filters and paginates", %{conn: conn, project: project, args: args} do
    matching = build(project, status: "failure", mix_env: "test", git_branch: "feature")
    build(project, status: "success", mix_env: "test", git_branch: "feature")

    assert %{"structuredContent" => %{"builds" => [%{"id" => ^matching}]}} =
             ListMixBuilds.call(
               conn,
               Map.merge(args, %{"status" => "failure", "mix_env" => "test", "git_branch" => "feature"})
             )

    assert %{"structuredContent" => %{"builds" => [_], "pagination_metadata" => %{"total_count" => 2}}} =
             ListMixBuilds.call(conn, Map.merge(args, %{"page" => 2, "page_size" => 1}))
  end

  defp build(project, attrs) do
    attrs = Map.new(attrs)
    id = Map.get(attrs, :id, UUIDv7.generate())

    {:ok, ^id} =
      Mix.create_build(
        Map.merge(
          %{id: id, project_id: project.id, account_id: project.account_id, duration_ms: 2_000, status: "success"},
          attrs
        )
      )

    Mix.Build.Buffer.flush()
    id
  end
end
