defmodule Tuist.MCP.AuthorizationTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.Accounts.AuthenticatedAccount
  alias Tuist.MCP.Components.Tools.GetTestRun
  alias Tuist.MCP.Components.Tools.UpdateTestCase
  alias Tuist.Tests
  alias Tuist.Tests.Analytics
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  # A Tuist operator reaching a customer's data over MCP authenticates with an
  # OAuth access token, which resolves to an `AuthenticatedAccount` in
  # `current_subject` — the subject MCP authorization consults first. The
  # operator grant hangs off the `%User{}` behind that token, so these exercise
  # the real principal selection rather than authorizing the user directly.

  setup do
    project = ProjectsFixtures.project_fixture(preload: [:account])
    operator = AccountsFixtures.user_fixture(email: "operator@tuist.dev", preload: [:account])

    stub(Tuist.Environment, :tuist_hosted?, fn -> false end)

    {:ok, project: project, operator: operator}
  end

  # The assigns an OAuth-token request actually carries: the token authenticates
  # as its account in `current_subject`, `current_user` is never set, and the
  # grant arrives under `:operator_grant_user` because that is where
  # `TuistWeb.OperatorGrant` puts the human it resolved. That the plug really
  # produces this shape from a real token is covered by
  # `TuistWeb.MCPOperatorGrantTest`.
  defp oauth_conn(operator, grant, scopes \\ ["mcp"]) do
    subject = %AuthenticatedAccount{
      account: operator.account,
      scopes: scopes,
      all_projects: false,
      project_ids: [],
      issued_by: operator
    }

    assigns =
      case grant do
        nil -> %{current_subject: subject}
        grant -> %{current_subject: subject, operator_grant_user: %{operator | operator_grant: grant}}
      end

    %Plug.Conn{assigns: assigns}
  end

  defp grant_for(account, tier \\ :read) do
    %{
      tier: tier,
      account_id: account.id,
      account_handle: account.name,
      sub: "operator@tuist.dev",
      jti: "1",
      exp: System.system_time(:second) + 600
    }
  end

  defp stub_test_run(project) do
    stub(Tests, :get_test, fn "run-1" ->
      {:ok,
       %{
         id: "run-1",
         status: :success,
         duration: 10_000,
         is_ci: true,
         is_flaky: false,
         scheme: "AppTests",
         git_branch: "main",
         git_commit_sha: "abc123",
         ran_at: ~N[2024-01-01 12:00:00],
         project_id: project.id
       }}
    end)

    stub(Analytics, :get_test_run_metrics, fn "run-1" ->
      %{total_count: 1, failed_count: 0, flaky_count: 0, avg_duration: 1}
    end)

    stub(Tuist.Storage, :generate_download_url, fn _key, _actor, _opts -> "https://storage.test/signed" end)
  end

  describe "an OAuth-token MCP session carrying an operator grant" do
    test "reads a customer project the grant covers", %{project: project, operator: operator} do
      stub_test_run(project)

      result = GetTestRun.call(oauth_conn(operator, grant_for(project.account)), %{"test_run_id" => "run-1"})

      assert %{"content" => [%{"type" => "text", "text" => text}]} = result
      refute Map.get(result, "isError")
      assert JSON.decode!(text)["id"] == "run-1"
    end

    test "is refused for a project the grant does not cover", %{project: project, operator: operator} do
      other_account = ProjectsFixtures.project_fixture(preload: [:account]).account
      stub_test_run(project)

      result = GetTestRun.call(oauth_conn(operator, grant_for(other_account)), %{"test_run_id" => "run-1"})

      assert %{"isError" => true} = result
    end

    test "is refused with no grant at all", %{project: project, operator: operator} do
      stub_test_run(project)

      result = GetTestRun.call(oauth_conn(operator, nil), %{"test_run_id" => "run-1"})

      assert %{"isError" => true} = result
    end

    # The grant widens which accounts are readable; it must not widen what the
    # credential may do. An `mcp`-scoped token stays read-only.
    # The grant widens which accounts a credential can see, not what it may do.
    # The MCP endpoint asks only that a credential authenticated, so a token
    # scoped elsewhere must not reach customer reads by presenting a grant.
    test "is refused when the token does not carry the mcp scope", %{project: project, operator: operator} do
      stub_test_run(project)

      result =
        GetTestRun.call(
          oauth_conn(operator, grant_for(project.account), ["project:admin:read"]),
          %{"test_run_id" => "run-1"}
        )

      assert %{"isError" => true} = result
    end

    # Presets expand outwards, so holding a member of the mcp group is not the
    # same as holding the group.
    test "is refused for a token scoped to an unrelated read scope", %{project: project, operator: operator} do
      stub_test_run(project)

      result =
        GetTestRun.call(
          oauth_conn(operator, grant_for(project.account), ["project:cache:read"]),
          %{"test_run_id" => "run-1"}
        )

      assert %{"isError" => true} = result
    end

    test "cannot write, even for the account the grant covers", %{project: project, operator: operator} do
      conn = oauth_conn(operator, grant_for(project.account, :admin))

      result =
        UpdateTestCase.call(conn, %{
          "account_handle" => project.account.name,
          "project_handle" => project.name,
          "identifier" => "AppTests/testExample",
          "state" => "muted"
        })

      assert %{"isError" => true} = result
    end
  end
end
