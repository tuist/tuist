defmodule TuistWeb.API.RunnersAndWebhooksControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.Accounts
  alias Tuist.Accounts.AuthenticatedAccount
  alias Tuist.FeatureFlags
  alias Tuist.Runners.Allowance
  alias Tuist.Runners.JobMetrics
  alias Tuist.Runners.Jobs
  alias Tuist.Runners.Profile
  alias Tuist.Runners.Profiles
  alias Tuist.Webhooks
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistWeb.Authentication

  setup do
    user = AccountsFixtures.user_fixture(preload: [:account])
    %{user: user, account: user.account}
  end

  test "gets a runner job with what its machine stopped for running out of memory", %{
    conn: conn,
    user: user,
    account: account
  } do
    account_id = account.id
    stub(FeatureFlags, :runners_enabled?, fn _account -> true end)
    stub(Jobs, :get_for_account, fn ^account_id, job_id -> {:ok, %{runner_job() | workflow_job_id: job_id}} end)

    :ok =
      JobMetrics.record(920_101, account_id, [
        oom_sample(1_750_000_000.0, 0, ""),
        oom_sample(1_750_000_015.0, 1, "java"),
        oom_sample(1_750_000_030.0, 1, "java")
      ])

    :ok = JobMetrics.record(920_102, account_id, [oom_sample(1_750_000_000.0, 0, "")])

    conn = Authentication.put_current_user(conn, user)

    response = conn |> get(~p"/api/accounts/#{account.name}/runners/jobs/920101") |> json_response(:ok)

    assert %{
             "kill_count" => 1,
             "first_kill_at" => "2025-06-15T15:06:55.000Z",
             "victim" => %{
               "process" => "java",
               "memory_bytes" => 27_917_287_424,
               "container" => "gradle-build",
               "image" => "gradle:8-jdk21"
             },
             "description" => description
           } = response["out_of_memory"]

    assert description =~ "It stopped java, which was using 27.9 GB, in the container gradle-build (gradle:8-jdk21)."
    assert description =~ "org.gradle.jvmargs"

    assert %{"out_of_memory" => nil} =
             conn |> get(~p"/api/accounts/#{account.name}/runners/jobs/920102") |> json_response(:ok)
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

  describe "API jobs" do
    setup %{account: account} do
      stub(FeatureFlags, :runners_enabled?, fn _account -> true end)
      stub(Allowance, :exhausted?, fn _account -> false end)
      {:ok, _} = Profiles.create(account, %{name: "ci", platform: :linux, vcpus: 4, memory_gb: 16})
      :ok
    end

    defp job_body(overrides \\ %{}) do
      Map.merge(
        %{
          profile: "ci",
          repository_url: "https://git.example.com/acme/app.git",
          commit_sha: String.duplicate("b", 40),
          ref: "refs/heads/main",
          name: "test",
          script: "mise run test",
          env: %{"PLAIN" => "visible"},
          secrets: %{"API_TOKEN" => "secret-value"},
          idempotency_key: "acme/app:bbbb:test"
        },
        overrides
      )
    end

    test "lets account tokens with runner write scope run, replay and cancel jobs", %{conn: conn, account: account} do
      conn =
        conn
        |> assign(:current_subject, %AuthenticatedAccount{account: account, scopes: ["account:runners:write"]})
        |> put_req_header("content-type", "application/json")

      created =
        conn
        |> post(~p"/api/accounts/#{account.name}/runners/jobs", job_body())
        |> json_response(:created)

      assert %{"status" => "queued", "repository" => "acme/app", "head_branch" => "main", "job_name" => "test"} = created
      refute inspect(created) =~ "secret-value"

      assert %{"workflow_job_id" => id} =
               conn
               |> post(~p"/api/accounts/#{account.name}/runners/jobs", job_body(%{script: "other"}))
               |> json_response(:ok)

      assert id == created["workflow_job_id"]

      assert %{"status" => "completed", "conclusion" => "cancelled"} =
               conn
               |> post(~p"/api/accounts/#{account.name}/runners/jobs/#{id}/cancel")
               |> json_response(:ok)
    end

    test "explains a job it cannot run", %{conn: conn, user: user, account: account} do
      conn = conn |> Authentication.put_current_user(user) |> put_req_header("content-type", "application/json")

      assert %{"message" => "No runner profile matches the profile field."} =
               conn
               |> post(~p"/api/accounts/#{account.name}/runners/jobs", job_body(%{profile: "missing"}))
               |> json_response(:unprocessable_entity)

      assert %{"message" => "repository_url must be an https URL without credentials"} =
               conn
               |> post(~p"/api/accounts/#{account.name}/runners/jobs", job_body(%{repository_url: "http://x.dev/a.git"}))
               |> json_response(:unprocessable_entity)

      conn
      |> post(~p"/api/accounts/#{account.name}/runners/jobs", Map.delete(job_body(), :script))
      |> json_response(:bad_request)

      stub(Allowance, :exhausted?, fn _account -> true end)

      conn
      |> post(~p"/api/accounts/#{account.name}/runners/jobs", job_body())
      |> json_response(:payment_required)
    end

    test "forbids runner readers from running or cancelling jobs", %{conn: conn, account: account} do
      conn =
        conn
        |> assign(:current_subject, %AuthenticatedAccount{account: account, scopes: ["account:runners:read"]})
        |> put_req_header("content-type", "application/json")

      conn |> post(~p"/api/accounts/#{account.name}/runners/jobs", job_body()) |> json_response(:forbidden)
      conn |> post(~p"/api/accounts/#{account.name}/runners/jobs/1/cancel") |> json_response(:forbidden)
    end
  end

  describe "runner profiles" do
    setup %{user: user, account: account} do
      stub(FeatureFlags, :runners_enabled?, fn _account -> true end)
      Tuist.Repo.insert!(%Profile{account_id: account.id, name: "ci", platform: :linux, vcpus: 7, memory_gb: 13})
      %{user: user}
    end

    test "lists and updates which branches save a profile's cache volumes", %{conn: conn, user: user, account: account} do
      conn = Authentication.put_current_user(conn, user)

      response = conn |> get(~p"/api/accounts/#{account.name}/runners/profiles") |> json_response(:ok)

      assert %{
               "cache_writer_all_branches" => true,
               "cache_writer_default_branch" => true,
               "cache_writer_branches" => []
             } =
               Enum.find(response["profiles"], &(&1["name"] == "ci"))

      response =
        conn
        |> put_req_header("content-type", "application/json")
        |> patch(~p"/api/accounts/#{account.name}/runners/profiles/ci", %{
          cache_writer_all_branches: false,
          cache_writer_default_branch: false,
          cache_writer_branches: ["develop", "release/*"]
        })
        |> json_response(:ok)

      assert %{
               "name" => "ci",
               "cache_writer_all_branches" => false,
               "cache_writer_default_branch" => false,
               "cache_writer_branches" => ["develop", "release/*"]
             } = response

      response =
        conn
        |> put_req_header("content-type", "application/json")
        |> patch(~p"/api/accounts/#{account.name}/runners/profiles/ci", %{cache_writer_branches: []})
        |> json_response(:ok)

      assert %{"cache_writer_default_branch" => false, "cache_writer_branches" => []} = response
      assert %{cache_writer_default_branch: false, cache_writer_branches: nil} = Profiles.get_by_name(account, "ci")
    end

    test "rejects invalid branches and unknown profiles", %{conn: conn, user: user, account: account} do
      conn = conn |> Authentication.put_current_user(user) |> put_req_header("content-type", "application/json")

      assert %{"message" => "cache_writer_branches must be branch names, optionally with * wildcards."} =
               conn
               |> patch(~p"/api/accounts/#{account.name}/runners/profiles/ci", %{cache_writer_branches: ["a b"]})
               |> json_response(:unprocessable_entity)

      conn
      |> patch(~p"/api/accounts/#{account.name}/runners/profiles/ci", %{cache_writer_default_branch: "sometimes"})
      |> json_response(:bad_request)

      assert %{"message" => "The runner profile was not found."} =
               conn
               |> patch(~p"/api/accounts/#{account.name}/runners/profiles/missing", %{cache_writer_branches: ["main"]})
               |> json_response(:not_found)

      assert %{cache_writer_branches: nil} = Profiles.get_by_name(account, "ci")
    end

    test "lists the shapes and Xcode versions profiles can use", %{conn: conn, user: user, account: account} do
      response =
        conn
        |> Authentication.put_current_user(user)
        |> get(~p"/api/accounts/#{account.name}/runners/catalog")
        |> json_response(:ok)

      assert %{"platform" => "linux", "vcpus" => 4, "memory_gb" => 8, "default" => false} in response["shapes"]
      assert %{"xcode_version" => "26.5", "default" => true} in response["xcode_versions"]
    end

    test "creates, resizes, and deletes a profile", %{conn: conn, user: user, account: account} do
      conn = conn |> Authentication.put_current_user(user) |> put_req_header("content-type", "application/json")

      assert %{
               "name" => "linux-4vcpu",
               "vcpus" => 4,
               "memory_gb" => 8,
               "protected" => false,
               "runs_on_label" => "tuist-linux-4vcpu"
             } =
               conn
               |> post(~p"/api/accounts/#{account.name}/runners/profiles", %{
                 name: "linux-4vcpu",
                 platform: "linux",
                 vcpus: 4,
                 memory_gb: 8,
                 protected: true
               })
               |> json_response(:created)

      assert %{"vcpus" => 8, "memory_gb" => 16, "cache_writer_default_branch" => true} =
               conn
               |> patch(~p"/api/accounts/#{account.name}/runners/profiles/linux-4vcpu", %{vcpus: 8, memory_gb: 16})
               |> json_response(:ok)

      assert conn |> delete(~p"/api/accounts/#{account.name}/runners/profiles/linux-4vcpu") |> response(:no_content)
      refute Profiles.get_by_name(account, "linux-4vcpu")
    end

    test "rejects unavailable shapes and protects default profiles", %{conn: conn, user: user, account: account} do
      conn = conn |> Authentication.put_current_user(user) |> put_req_header("content-type", "application/json")

      assert %{"message" => "vcpus and memory_gb must match an available linux shape: 1 vCPU / 2 GB" <> _} =
               conn
               |> post(~p"/api/accounts/#{account.name}/runners/profiles", %{
                 name: "odd",
                 platform: "linux",
                 vcpus: 3,
                 memory_gb: 8
               })
               |> json_response(:unprocessable_entity)

      conn
      |> post(~p"/api/accounts/#{account.name}/runners/profiles", %{name: "odd", vcpus: 2, memory_gb: 8})
      |> json_response(:bad_request)

      Tuist.Repo.insert!(%Profile{
        account_id: account.id,
        name: "base",
        platform: :linux,
        vcpus: 2,
        memory_gb: 8,
        protected: true
      })

      assert %{"message" => "This profile is a default and can't be deleted."} =
               conn
               |> delete(~p"/api/accounts/#{account.name}/runners/profiles/base")
               |> json_response(:unprocessable_entity)

      assert %{"message" => "The runner profile was not found."} =
               conn
               |> delete(~p"/api/accounts/#{account.name}/runners/profiles/missing")
               |> json_response(:not_found)
    end

    test "lets account tokens with runner write scope manage profiles", %{conn: conn, account: account} do
      conn =
        conn
        |> assign(:current_subject, %AuthenticatedAccount{account: account, scopes: ["account:runners:write"]})
        |> put_req_header("content-type", "application/json")

      assert %{"runs_on_label" => "tuist-linux-4vcpu"} =
               conn
               |> post(~p"/api/accounts/#{account.name}/runners/profiles", %{
                 name: "linux-4vcpu",
                 platform: "linux",
                 vcpus: 4,
                 memory_gb: 8
               })
               |> json_response(:created)

      assert %{"vcpus" => 8, "memory_gb" => 16} =
               conn
               |> patch(~p"/api/accounts/#{account.name}/runners/profiles/linux-4vcpu", %{vcpus: 8, memory_gb: 16})
               |> json_response(:ok)

      assert %{"profiles" => [_ | _]} =
               conn |> get(~p"/api/accounts/#{account.name}/runners/profiles") |> json_response(:ok)

      assert conn |> delete(~p"/api/accounts/#{account.name}/runners/profiles/linux-4vcpu") |> response(:no_content)
      refute Profiles.get_by_name(account, "linux-4vcpu")
    end

    test "lets runner readers list profiles but not change them", %{
      conn: conn,
      account: account
    } do
      response =
        conn
        |> assign(:current_subject, %AuthenticatedAccount{account: account, scopes: ["account:runners:read"]})
        |> get(~p"/api/accounts/#{account.name}/runners/profiles")
        |> json_response(:ok)

      assert %{"runs_on_label" => "tuist-ci"} = Enum.find(response["profiles"], &(&1["name"] == "ci"))

      conn
      |> assign(:current_subject, %AuthenticatedAccount{account: account, scopes: ["account:runners:read"]})
      |> put_req_header("content-type", "application/json")
      |> patch(~p"/api/accounts/#{account.name}/runners/profiles/ci", %{cache_writer_branches: ["*"]})
      |> json_response(:forbidden)

      assert %{cache_writer_branches: nil} = Profiles.get_by_name(account, "ci")

      conn
      |> assign(:current_subject, %AuthenticatedAccount{account: account, scopes: ["account:runners:read"]})
      |> put_req_header("content-type", "application/json")
      |> post(~p"/api/accounts/#{account.name}/runners/profiles", %{
        name: "new",
        platform: "linux",
        vcpus: 2,
        memory_gb: 8
      })
      |> json_response(:forbidden)

      conn
      |> assign(:current_subject, %AuthenticatedAccount{account: account, scopes: ["account:runners:read"]})
      |> delete(~p"/api/accounts/#{account.name}/runners/profiles/ci")
      |> json_response(:forbidden)

      refute Profiles.get_by_name(account, "new")
      assert Profiles.get_by_name(account, "ci")
    end
  end

  defp oom_sample(timestamp, kill_count, process) do
    %{
      timestamp: timestamp,
      oom_kill_count: kill_count,
      oom_victim_process: process,
      oom_victim_memory_bytes: if(process == "", do: 0, else: 27_917_287_424),
      oom_victim_container: if(process == "", do: "", else: "gradle-build"),
      oom_victim_image: if(process == "", do: "", else: "gradle:8-jdk21")
    }
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
