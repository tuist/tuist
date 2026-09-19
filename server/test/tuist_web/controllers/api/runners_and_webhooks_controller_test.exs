defmodule TuistWeb.API.RunnersAndWebhooksControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.Accounts
  alias Tuist.Accounts.AuthenticatedAccount
  alias Tuist.FeatureFlags
  alias Tuist.Runners.Jobs
  alias Tuist.Webhooks
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistWeb.Authentication

  setup do
    user = AccountsFixtures.user_fixture(preload: [:account])
    %{user: user, account: user.account}
  end

  test "lists account-scoped runner jobs without internal runtime identifiers", %{
    conn: conn,
    user: user,
    account: account
  } do
    account_id = account.id
    stub(FeatureFlags, :runners_enabled?, fn _account -> true end)
    stub(Jobs, :count_for_account, fn ^account_id, [] -> 1 end)
    stub(Jobs, :list_for_account, fn ^account_id, [limit: 20, offset: 0] -> [runner_job()] end)

    response =
      conn
      |> Authentication.put_current_user(user)
      |> get(~p"/api/accounts/#{account.name}/runners/jobs")
      |> json_response(:ok)

    assert [%{"workflow_job_id" => 42, "platform" => "linux"}] = response["jobs"]
    refute Map.has_key?(hd(response["jobs"]), "fleet_name")
    refute Map.has_key?(hd(response["jobs"]), "pod_name")
    refute Map.has_key?(hd(response["jobs"]), "runner_name")
  end

  test "allows an account token with runner read scope to list its account's jobs", %{conn: conn, account: account} do
    account_id = account.id
    stub(FeatureFlags, :runners_enabled?, fn _account -> true end)
    stub(Jobs, :count_for_account, fn ^account_id, [] -> 0 end)
    stub(Jobs, :list_for_account, fn ^account_id, [limit: 20, offset: 0] -> [] end)

    response =
      conn
      |> assign(:current_subject, %AuthenticatedAccount{account: account, scopes: ["account:runners:read"]})
      |> get(~p"/api/accounts/#{account.name}/runners/jobs")
      |> json_response(:ok)

    assert response["jobs"] == []
  end

  test "forbids an account token without runner read scope", %{conn: conn, account: account} do
    response =
      conn
      |> assign(:current_subject, %AuthenticatedAccount{account: account, scopes: ["project:admin:read"]})
      |> get(~p"/api/accounts/#{account.name}/runners/jobs")
      |> json_response(:forbidden)

    assert response["message"] =~ "not authorized"
  end

  test "forbids an account token with runner read scope from another private account", %{conn: conn, account: account} do
    other_account = AccountsFixtures.organization_fixture(preload: [:account]).account

    response =
      conn
      |> assign(:current_subject, %AuthenticatedAccount{account: account, scopes: ["account:runners:read"]})
      |> get(~p"/api/accounts/#{other_account.name}/runners/jobs")
      |> json_response(:forbidden)

    assert response["message"] =~ "not authorized"
  end

  test "allows authenticated callers to list jobs for a public account", %{conn: conn, account: account} do
    {:ok, account} = Accounts.update_account_visibility(account, :public)
    other_account = AccountsFixtures.organization_fixture(preload: [:account]).account
    account_id = account.id

    stub(FeatureFlags, :runners_enabled?, fn _account -> true end)
    stub(Jobs, :count_for_account, fn ^account_id, [] -> 0 end)
    stub(Jobs, :list_for_account, fn ^account_id, [limit: 20, offset: 0] -> [] end)

    response =
      conn
      |> assign(:current_subject, %AuthenticatedAccount{account: other_account, scopes: []})
      |> get(~p"/api/accounts/#{account.name}/runners/jobs")
      |> json_response(:ok)

    assert response["jobs"] == []
  end

  test "lists webhook endpoints without their signing secrets", %{conn: conn, user: user, account: account} do
    account_id = account.id

    endpoint = %{
      id: Ecto.UUID.generate(),
      name: "Build notifications",
      url: "https://example.com/hooks/builds",
      signing_secret: "plaintext-signing-secret",
      signing_secret_last_four: "abcd",
      event_types: ["build.created"],
      inserted_at: ~U[2026-08-28 10:00:00Z],
      updated_at: ~U[2026-08-28 10:00:00Z]
    }

    stub(Webhooks, :list_endpoints, fn ^account_id -> [endpoint] end)

    response =
      conn
      |> Authentication.put_current_user(user)
      |> get(~p"/api/accounts/#{account.name}/webhooks")
      |> json_response(:ok)

    assert [%{"id" => id, "signing_secret_last_four" => "abcd"}] = response["endpoints"]
    assert id == endpoint.id
    refute inspect(response) =~ "plaintext-signing-secret"
  end

  defp runner_job do
    %{
      workflow_job_id: 42,
      repository: "acme/app",
      workflow_run_id: 7,
      workflow_name: "Test",
      run_attempt: 1,
      job_name: "Unit tests",
      head_branch: "main",
      head_sha: "abc",
      status: "completed",
      conclusion: "success",
      fleet_name: "linux-internal",
      platform: "linux",
      vcpus: 4,
      memory_gb: 16,
      requested_dispatch_label: "tuist-linux",
      pod_name: "runner-pod",
      runner_name: "runner-1",
      enqueued_at: ~U[2026-08-28 10:00:00Z],
      claimed_at: nil,
      started_at: ~U[2026-08-28 10:00:01Z],
      completed_at: ~U[2026-08-28 10:01:00Z],
      log_archived_at: nil,
      updated_at: ~U[2026-08-28 10:01:00Z]
    }
  end
end
