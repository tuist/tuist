defmodule Tuist.MCP.Components.Tools.RunnerAndWebhookToolsTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.Accounts
  alias Tuist.FeatureFlags
  alias Tuist.MCP.Components.Tools.CreateRunnerProfile
  alias Tuist.MCP.Components.Tools.DeleteRunnerProfile
  alias Tuist.MCP.Components.Tools.GetRunnerJob
  alias Tuist.MCP.Components.Tools.GetWebhookEndpoint
  alias Tuist.MCP.Components.Tools.ListRunnerJobs
  alias Tuist.MCP.Components.Tools.ListRunnerProfileOptions
  alias Tuist.MCP.Components.Tools.ListRunnerProfiles
  alias Tuist.MCP.Components.Tools.ListWebhookEndpoints
  alias Tuist.MCP.Components.Tools.UpdateRunnerProfile
  alias Tuist.Repo
  alias Tuist.Runners.Jobs
  alias Tuist.Runners.Profile
  alias Tuist.Runners.Profiles
  alias Tuist.Webhooks
  alias TuistTestSupport.Fixtures.AccountsFixtures

  describe "list_runner_jobs" do
    test "uses the runner permission and account-scoped query" do
      account = %{id: 1, name: "acme"}
      job = runner_job_fixture()

      stub(Accounts, :get_account_by_handle, fn "acme" -> account end)
      stub(Tuist.Authorization, :authorize, fn :runners_read, :subject, ^account -> :ok end)
      stub(FeatureFlags, :runners_enabled?, fn ^account -> true end)
      stub(Jobs, :count_for_account, fn 1, [] -> 1 end)
      stub(Jobs, :list_for_account, fn 1, [limit: 20, offset: 0] -> [job] end)

      conn = %Plug.Conn{assigns: %{current_subject: :subject}}

      assert %{"content" => [%{"type" => "text", "text" => text}]} =
               ListRunnerJobs.call(conn, %{"account_handle" => "acme"})

      assert %{"jobs" => [%{"workflow_job_id" => 42, "repository" => "acme/app"}]} = JSON.decode!(text)

      refute JSON.decode!(text)["jobs"] |> hd() |> Map.has_key?("fleet_name")
      refute JSON.decode!(text)["jobs"] |> hd() |> Map.has_key?("pod_name")
      refute JSON.decode!(text)["jobs"] |> hd() |> Map.has_key?("runner_name")
    end
  end

  describe "get_runner_job" do
    test "uses the account-scoped job lookup" do
      account = %{id: 1, name: "acme"}

      stub(Accounts, :get_account_by_handle, fn "acme" -> account end)
      stub(Tuist.Authorization, :authorize, fn :runners_read, :subject, ^account -> :ok end)
      stub(FeatureFlags, :runners_enabled?, fn ^account -> true end)
      stub(Jobs, :get_for_account, fn 1, 42 -> {:ok, runner_job_fixture()} end)

      conn = %Plug.Conn{assigns: %{current_subject: :subject}}

      assert %{"content" => [%{"type" => "text", "text" => text}]} =
               GetRunnerJob.call(conn, %{"account_handle" => "acme", "workflow_job_id" => 42})

      assert JSON.decode!(text)["workflow_job_id"] == 42
    end

    test "rejects malformed arguments before querying runner data" do
      conn = %Plug.Conn{assigns: %{current_subject: :subject}}

      assert %{
               "content" => [%{"type" => "text", "text" => "Arguments do not match the tool schema."}],
               "isError" => true
             } =
               GetRunnerJob.call(conn, %{"account_handle" => "acme", "workflow_job_id" => "42"})
    end
  end

  describe "webhook endpoint tools" do
    test "use the same administrative account permission as the dashboard and never return the signing secret" do
      account = %{id: 1, name: "acme"}
      endpoint = webhook_endpoint_fixture()

      stub(Accounts, :get_account_by_handle, fn "acme" -> account end)
      stub(Tuist.Authorization, :authorize, fn :account_update, :subject, ^account -> :ok end)
      stub(Webhooks, :list_endpoints, fn 1 -> [endpoint] end)

      conn = %Plug.Conn{assigns: %{current_subject: :subject}}

      assert %{"content" => [%{"type" => "text", "text" => text}]} =
               ListWebhookEndpoints.call(conn, %{"account_handle" => "acme"})

      refute inspect(JSON.decode!(text)) =~ "plaintext-signing-secret"
    end

    test "scopes an endpoint identifier to the authorized account" do
      account = %{id: 1, name: "acme"}
      endpoint = webhook_endpoint_fixture()

      stub(Accounts, :get_account_by_handle, fn "acme" -> account end)
      stub(Tuist.Authorization, :authorize, fn :account_update, :subject, ^account -> :ok end)
      stub(Webhooks, :get_account_endpoint, fn "0d574fe6-8908-4c8f-9413-b1d54a4aa465", 1 -> {:ok, endpoint} end)

      conn = %Plug.Conn{assigns: %{current_subject: :subject}}

      assert %{"content" => [%{"type" => "text", "text" => text}]} =
               GetWebhookEndpoint.call(conn, %{
                 "account_handle" => "acme",
                 "webhook_endpoint_id" => "0d574fe6-8908-4c8f-9413-b1d54a4aa465"
               })

      assert JSON.decode!(text)["id"] == "0d574fe6-8908-4c8f-9413-b1d54a4aa465"
    end

    test "rejects an invalid endpoint identifier before the database lookup" do
      conn = %Plug.Conn{assigns: %{current_subject: :subject}}

      assert %{
               "content" => [%{"type" => "text", "text" => "Webhook endpoint identifier must be a UUID."}],
               "isError" => true
             } =
               GetWebhookEndpoint.call(conn, %{
                 "account_handle" => "acme",
                 "webhook_endpoint_id" => "https://tuist.dev/acme/webhooks"
               })
    end
  end

  describe "runner profile tools" do
    setup do
      account = AccountsFixtures.organization_fixture(preload: [:account]).account
      account_id = account.id
      stub(Tuist.Authorization, :authorize, fn :account_update, :subject, %{id: ^account_id} -> :ok end)
      stub(FeatureFlags, :runners_enabled?, fn _account -> true end)
      %{account: account, conn: %Plug.Conn{assigns: %{current_subject: :subject}}}
    end

    test "list and update cache branches with the administrative account permission", %{account: account, conn: conn} do
      profile =
        Repo.insert!(%Profile{account_id: account.id, name: "ci", platform: :linux, vcpus: 7, memory_gb: 13})

      assert %{"content" => [%{"text" => text}]} =
               ListRunnerProfiles.call(conn, %{"account_handle" => account.name})

      assert %{
               "name" => "ci",
               "runs_on_label" => "tuist-ci",
               "cache_writer_default_branch" => true,
               "cache_writer_branches" => []
             } = Enum.find(JSON.decode!(text)["profiles"], &(&1["name"] == "ci"))

      arguments = %{"account_handle" => account.name, "profile_name" => "ci"}

      assert %{"content" => [%{"text" => text}]} =
               UpdateRunnerProfile.call(
                 conn,
                 Map.merge(arguments, %{
                   "cache_writer_default_branch" => false,
                   "cache_writer_branches" => ["develop", "release/*"]
                 })
               )

      assert %{
               "cache_writer_default_branch" => false,
               "cache_writer_branches" => ["develop", "release/*"]
             } = JSON.decode!(text)

      assert %{cache_writer_default_branch: false, cache_writer_branches: ["develop", "release/*"]} =
               Repo.get!(Profile, profile.id)

      assert %{"content" => [%{"text" => text}]} =
               UpdateRunnerProfile.call(conn, Map.put(arguments, "cache_writer_branches", []))

      assert %{"cache_writer_default_branch" => false, "cache_writer_branches" => []} = JSON.decode!(text)

      assert %{"content" => [%{"text" => text}]} =
               UpdateRunnerProfile.call(conn, Map.put(arguments, "cache_writer_default_branch", true))

      assert %{"cache_writer_default_branch" => true, "cache_writer_branches" => []} = JSON.decode!(text)

      assert %{
               "isError" => true,
               "content" => [%{"text" => "cache_writer_branches must be branch names, optionally with * wildcards."}]
             } = UpdateRunnerProfile.call(conn, Map.put(arguments, "cache_writer_branches", ["a b"]))

      assert %{"isError" => true, "content" => [%{"text" => "The runner profile was not found."}]} =
               UpdateRunnerProfile.call(conn, %{
                 "account_handle" => account.name,
                 "profile_name" => "missing",
                 "cache_writer_branches" => ["main"]
               })
    end

    test "lists the shapes and Xcode versions profiles can use", %{account: account, conn: conn} do
      stub(Tuist.Authorization, :authorize, fn _action, :subject, _account -> :ok end)

      assert %{"content" => [%{"text" => text}]} =
               ListRunnerProfileOptions.call(conn, %{"account_handle" => account.name})

      assert %{"shapes" => shapes, "xcode_versions" => xcode_versions} = JSON.decode!(text)
      assert %{"platform" => "linux", "vcpus" => 4, "memory_gb" => 8, "default" => false} in shapes
      assert %{"platform" => "macos", "vcpus" => 6, "memory_gb" => 14, "default" => true} in shapes
      assert %{"xcode_version" => "26.5", "default" => true} in xcode_versions
    end

    test "creates a profile and returns its runs-on label", %{account: account, conn: conn} do
      arguments = %{
        "account_handle" => account.name,
        "name" => "linux-4vcpu",
        "platform" => "linux",
        "vcpus" => 4,
        "memory_gb" => 8
      }

      assert %{"content" => [%{"text" => text}]} = CreateRunnerProfile.call(conn, arguments)

      assert %{
               "name" => "linux-4vcpu",
               "platform" => "linux",
               "vcpus" => 4,
               "memory_gb" => 8,
               "protected" => false,
               "runs_on_label" => "tuist-linux-4vcpu"
             } = JSON.decode!(text)

      assert %{vcpus: 4, memory_gb: 8} = Repo.get_by!(Profile, account_id: account.id, name: "linux-4vcpu")

      assert %{"isError" => true, "content" => [%{"text" => "A profile with this name already exists in this account."}]} =
               CreateRunnerProfile.call(conn, arguments)
    end

    test "lists the available shapes when the requested one isn't in the catalog", %{account: account, conn: conn} do
      assert %{"isError" => true, "content" => [%{"text" => text}]} =
               CreateRunnerProfile.call(conn, %{
                 "account_handle" => account.name,
                 "name" => "huge",
                 "platform" => "linux",
                 "vcpus" => 3,
                 "memory_gb" => 8
               })

      assert text =~ "vcpus and memory_gb must match an available linux shape: 1 vCPU / 2 GB, 2 vCPU / 4 GB"
      assert text =~ "4 vCPU / 8 GB"

      assert %{"isError" => true, "content" => [%{"text" => text}]} =
               CreateRunnerProfile.call(conn, %{
                 "account_handle" => account.name,
                 "name" => "old-xcode",
                 "platform" => "macos",
                 "vcpus" => 6,
                 "memory_gb" => 14,
                 "xcode_version" => "15.0"
               })

      assert text =~ "xcode_version must be one of: 26.5, 26.4.1"
    end

    test "refuses to create a profile past the account limit", %{account: account, conn: conn} do
      existing = account |> Profiles.list_for_account() |> length()

      for index <- existing..(Profiles.max_per_account() - 1)//1 do
        Repo.insert!(%Profile{account_id: account.id, name: "p#{index}", platform: :linux, vcpus: 2, memory_gb: 8})
      end

      assert %{"isError" => true, "content" => [%{"text" => "The account already has the maximum of 10" <> _}]} =
               CreateRunnerProfile.call(conn, %{
                 "account_handle" => account.name,
                 "name" => "one-more",
                 "platform" => "linux",
                 "vcpus" => 2,
                 "memory_gb" => 8
               })
    end

    test "changes a profile's shape and validates it against the catalog", %{account: account, conn: conn} do
      Repo.insert!(%Profile{account_id: account.id, name: "ci", platform: :linux, vcpus: 2, memory_gb: 8})
      arguments = %{"account_handle" => account.name, "profile_name" => "ci"}

      assert %{"content" => [%{"text" => text}]} =
               UpdateRunnerProfile.call(conn, Map.merge(arguments, %{"vcpus" => 8, "memory_gb" => 32}))

      assert %{"vcpus" => 8, "memory_gb" => 32, "cache_writer_default_branch" => true} = JSON.decode!(text)

      assert %{
               "isError" => true,
               "content" => [%{"text" => "vcpus and memory_gb must match an available linux shape" <> _}]
             } =
               UpdateRunnerProfile.call(conn, Map.put(arguments, "vcpus", 5))

      assert %{vcpus: 8, memory_gb: 32} = Repo.get_by!(Profile, account_id: account.id, name: "ci")
    end

    test "deletes a profile but not a default one", %{account: account, conn: conn} do
      Repo.insert!(%Profile{account_id: account.id, name: "ci", platform: :linux, vcpus: 2, memory_gb: 8})

      Repo.insert!(%Profile{
        account_id: account.id,
        name: "base",
        platform: :linux,
        vcpus: 2,
        memory_gb: 8,
        protected: true
      })

      assert %{"content" => [%{"text" => text}]} =
               DeleteRunnerProfile.call(conn, %{"account_handle" => account.name, "profile_name" => "ci"})

      assert %{"name" => "ci"} = JSON.decode!(text)
      refute Repo.get_by(Profile, account_id: account.id, name: "ci")

      assert %{"isError" => true, "content" => [%{"text" => "This profile is a default and can't be deleted."}]} =
               DeleteRunnerProfile.call(conn, %{"account_handle" => account.name, "profile_name" => "base"})

      assert Repo.get_by(Profile, account_id: account.id, name: "base")
    end

    test "refuses callers without account administration", %{account: account, conn: conn} do
      stub(Tuist.Authorization, :authorize, fn _action, :subject, _account -> {:error, :forbidden} end)
      reject(&Profiles.create/2)
      reject(&Profiles.update/2)
      reject(&Profiles.delete/1)

      assert %{"isError" => true} =
               CreateRunnerProfile.call(conn, %{
                 "account_handle" => account.name,
                 "name" => "ci",
                 "platform" => "linux",
                 "vcpus" => 2,
                 "memory_gb" => 8
               })

      assert %{"isError" => true} =
               UpdateRunnerProfile.call(conn, %{
                 "account_handle" => account.name,
                 "profile_name" => "linux",
                 "cache_writer_branches" => ["*"]
               })

      assert %{"isError" => true} =
               DeleteRunnerProfile.call(conn, %{"account_handle" => account.name, "profile_name" => "linux"})
    end
  end

  defp runner_job_fixture do
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
      fleet_name: "linux",
      platform: "linux",
      vcpus: 4,
      memory_gb: 16,
      requested_dispatch_label: "tuist-linux",
      pod_name: "pod",
      runner_name: "runner",
      enqueued_at: ~U[2026-08-28 10:00:00Z],
      claimed_at: nil,
      started_at: ~U[2026-08-28 10:00:01Z],
      completed_at: ~U[2026-08-28 10:01:00Z],
      log_archived_at: nil,
      updated_at: ~U[2026-08-28 10:01:00Z]
    }
  end

  defp webhook_endpoint_fixture do
    %{
      id: "0d574fe6-8908-4c8f-9413-b1d54a4aa465",
      name: "Build notifications",
      url: "https://example.com/hooks/builds",
      signing_secret: "plaintext-signing-secret",
      signing_secret_last_four: "abcd",
      event_types: ["build.created"],
      inserted_at: ~U[2026-08-28 10:00:00Z],
      updated_at: ~U[2026-08-28 10:00:00Z]
    }
  end
end
