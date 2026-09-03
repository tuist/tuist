defmodule Tuist.Runners.BuildkiteTest do
  use TuistTestSupport.Cases.DataCase, async: true

  import Ecto.Query
  import Mimic

  alias Tuist.FeatureFlags
  alias Tuist.Repo
  alias Tuist.Runners.Allowance
  alias Tuist.Runners.Buildkite
  alias Tuist.Runners.Buildkite.Client
  alias Tuist.Runners.Buildkite.Job
  alias Tuist.Runners.Catalog
  alias Tuist.Runners.Dispatch
  alias Tuist.Runners.Profile
  alias Tuist.Runners.Profiles
  alias Tuist.Runners.WorkflowJob
  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup :verify_on_exit!

  setup do
    stub(Catalog, :default_xcode_version, fn -> nil end)
    stub(FeatureFlags, :runners_enabled?, fn _account -> true end)
    stub(Allowance, :exhausted?, fn _account -> false end)

    %{account: account} =
      AccountsFixtures.organization_fixture(
        name: "buildkite-org-#{System.unique_integer([:positive])}",
        preload: [:account]
      )

    [profile] = Profiles.list_for_account(account)
    queue_key = Profile.dispatch_label(profile)

    stub(Dispatch, :resolve_dispatch_target, fn _account, [^queue_key] ->
      {:ok,
       %{
         pool_name: "pool-macos",
         requested_dispatch_label: queue_key,
         platform: :macos,
         vcpus: 4,
         memory_gb: 16
       }}
    end)

    {:ok, installation} =
      Buildkite.upsert_installation(account.id, %{
        organization_slug: "acme",
        stack_key: "tuist-#{System.unique_integer([:positive])}",
        agent_token: "bkct_secret"
      })

    %{account: account, installation: installation, queue_key: queue_key}
  end

  defp scheduled_job(overrides \\ %{}) do
    Map.merge(
      %{
        job_uuid: Ecto.UUID.generate(),
        priority: 0,
        agent_query_rules: [],
        scheduled_at: DateTime.utc_now(),
        pipeline_slug: "ios",
        build_uuid: Ecto.UUID.generate(),
        build_number: 42,
        build_branch: "main",
        step_key: "test",
        queue_key: "queue"
      },
      overrides
    )
  end

  describe "poll/1" do
    test "reserves scheduled jobs and queues them for dispatch", %{
      installation: installation,
      account: account,
      queue_key: queue_key
    } do
      job = scheduled_job(%{queue_key: queue_key})

      expect(Client, :list_scheduled_jobs, fn _installation, ^queue_key, _limit ->
        {:ok, %{jobs: [job], dispatch_paused: false}}
      end)

      expect(Client, :reserve, fn _installation, uuids, _expiry ->
        assert uuids == [job.job_uuid]
        {:ok, [job.job_uuid]}
      end)

      assert {:ok, 1} = Buildkite.poll(installation)

      mapping = Repo.one(from(j in Job, where: j.job_uuid == ^job.job_uuid))
      assert mapping.account_id == account.id
      assert mapping.build_number == 42

      lifecycle = Repo.get(WorkflowJob, mapping.workflow_job_id)
      assert lifecycle.status == "queued"
      assert lifecycle.provider == "buildkite"
      assert lifecycle.fleet_name == "pool-macos"
      assert lifecycle.head_branch == "main"
    end

    test "assigns a surrogate id above GitHub's keyspace", %{
      installation: installation,
      queue_key: queue_key
    } do
      job = scheduled_job(%{queue_key: queue_key})

      stub(Client, :list_scheduled_jobs, fn _installation, _queue, _limit ->
        {:ok, %{jobs: [job], dispatch_paused: false}}
      end)

      stub(Client, :reserve, fn _installation, uuids, _expiry -> {:ok, uuids} end)

      assert {:ok, 1} = Buildkite.poll(installation)

      mapping = Repo.one(from(j in Job, where: j.job_uuid == ^job.job_uuid))
      assert mapping.workflow_job_id >= 1_000_000_000_000_000
    end

    test "leaves a paused queue alone", %{installation: installation, queue_key: queue_key} do
      stub(Client, :list_scheduled_jobs, fn _installation, ^queue_key, _limit ->
        {:ok, %{jobs: [scheduled_job()], dispatch_paused: true}}
      end)

      reject(&Client.reserve/3)

      assert {:ok, 0} = Buildkite.poll(installation)
    end

    test "does not queue a job another stack reserved first", %{
      installation: installation,
      queue_key: queue_key
    } do
      job = scheduled_job(%{queue_key: queue_key})

      stub(Client, :list_scheduled_jobs, fn _installation, _queue, _limit ->
        {:ok, %{jobs: [job], dispatch_paused: false}}
      end)

      stub(Client, :reserve, fn _installation, _uuids, _expiry -> {:ok, []} end)

      assert {:ok, 0} = Buildkite.poll(installation)
      assert Repo.aggregate(from(j in Job, where: j.job_uuid == ^job.job_uuid), :count) == 0
    end

    test "does not re-queue a job it already holds", %{
      installation: installation,
      queue_key: queue_key
    } do
      job = scheduled_job(%{queue_key: queue_key})

      stub(Client, :list_scheduled_jobs, fn _installation, _queue, _limit ->
        {:ok, %{jobs: [job], dispatch_paused: false}}
      end)

      stub(Client, :reserve, fn _installation, uuids, _expiry -> {:ok, uuids} end)

      assert {:ok, 1} = Buildkite.poll(installation)
      assert {:ok, 0} = Buildkite.poll(installation)

      assert Repo.aggregate(from(j in Job, where: j.job_uuid == ^job.job_uuid), :count) == 1
    end

    test "declines a queue that names a Linux profile", %{
      installation: installation,
      queue_key: queue_key
    } do
      # The Linux job container holds no ServiceAccount token, which the
      # Buildkite lane needs from inside the job to report its log and
      # window. Reserving would strand the job on a queue nothing serves.
      stub(Dispatch, :resolve_dispatch_target, fn _account, [^queue_key] ->
        {:ok,
         %{
           pool_name: "pool-linux",
           requested_dispatch_label: queue_key,
           platform: :linux,
           vcpus: 4,
           memory_gb: 16
         }}
      end)

      stub(Client, :list_scheduled_jobs, fn _installation, _queue, _limit ->
        {:ok, %{jobs: [scheduled_job()], dispatch_paused: false}}
      end)

      reject(&Client.reserve/3)

      assert {:ok, 0} = Buildkite.poll(installation)
    end

    test "stops the pass when the agent token is rejected", %{installation: installation} do
      stub(Client, :list_scheduled_jobs, fn _installation, _queue, _limit ->
        {:error, :unauthorized}
      end)

      assert {:error, :unauthorized} = Buildkite.poll(installation)
    end

    test "is a no-op when the account's allowance is exhausted", %{installation: installation} do
      stub(Allowance, :exhausted?, fn _account -> true end)
      reject(&Client.list_scheduled_jobs/3)

      assert {:error, :allowance_exhausted} = Buildkite.poll(installation)
    end

    test "is a no-op when runners are disabled for the account", %{installation: installation} do
      stub(FeatureFlags, :runners_enabled?, fn _account -> false end)
      reject(&Client.list_scheduled_jobs/3)

      assert {:error, :runners_disabled} = Buildkite.poll(installation)
    end
  end

  describe "poll/1 reservation renewal" do
    setup %{installation: installation, queue_key: queue_key} do
      job = scheduled_job(%{queue_key: queue_key})

      stub(Client, :list_scheduled_jobs, fn _installation, _queue, _limit ->
        {:ok, %{jobs: [job], dispatch_paused: false}}
      end)

      stub(Client, :reserve, fn _installation, uuids, _expiry -> {:ok, uuids} end)
      assert {:ok, 1} = Buildkite.poll(installation)

      lapsed = DateTime.add(DateTime.utc_now(), -60, :second)

      Repo.update_all(
        from(j in Job, where: j.job_uuid == ^job.job_uuid),
        set: [reserved_until: DateTime.truncate(lapsed, :second)]
      )

      %{job: job}
    end

    test "retakes a job whose reservation lapsed while it waited", %{
      installation: installation,
      job: job
    } do
      stub(Client, :list_scheduled_jobs, fn _installation, _queue, _limit ->
        {:ok, %{jobs: [], dispatch_paused: false}}
      end)

      expect(Client, :reserve, fn _installation, uuids, _expiry ->
        assert uuids == [job.job_uuid]
        {:ok, uuids}
      end)

      assert {:ok, 0} = Buildkite.poll(installation)

      mapping = Repo.one(from(j in Job, where: j.job_uuid == ^job.job_uuid))
      assert DateTime.after?(mapping.reserved_until, DateTime.utc_now())
    end

    test "completes a job that did not come back after its reservation lapsed", %{
      installation: installation,
      job: job
    } do
      stub(Client, :list_scheduled_jobs, fn _installation, _queue, _limit ->
        {:ok, %{jobs: [], dispatch_paused: false}}
      end)

      stub(Client, :reserve, fn _installation, _uuids, _expiry -> {:ok, []} end)

      assert {:ok, 0} = Buildkite.poll(installation)

      mapping = Repo.one(from(j in Job, where: j.job_uuid == ^job.job_uuid))
      assert Repo.get(WorkflowJob, mapping.workflow_job_id).status == "cancelled"
    end
  end

  describe "job_trusted?/2" do
    setup %{installation: installation, account: account, queue_key: queue_key} do
      job = scheduled_job(%{queue_key: queue_key})

      stub(Client, :list_scheduled_jobs, fn _installation, _queue, _limit ->
        {:ok, %{jobs: [job], dispatch_paused: false}}
      end)

      stub(Client, :reserve, fn _installation, uuids, _expiry -> {:ok, uuids} end)
      assert {:ok, 1} = Buildkite.poll(installation)

      mapping = Repo.one(from(j in Job, where: j.job_uuid == ^job.job_uuid))
      %{account: account, workflow_job_id: mapping.workflow_job_id}
    end

    test "trusts a job with no pull-request repository", %{
      account: account,
      workflow_job_id: workflow_job_id
    } do
      stub(Client, :get_job, fn _installation, _uuid ->
        {:ok, %{"env" => %{"BUILDKITE_REPO" => "git@github.com:acme/ios.git"}}}
      end)

      assert Buildkite.job_trusted?(account.id, workflow_job_id)
    end

    test "trusts a same-repository pull request across remote spellings", %{
      account: account,
      workflow_job_id: workflow_job_id
    } do
      stub(Client, :get_job, fn _installation, _uuid ->
        {:ok,
         %{
           "env" => %{
             "BUILDKITE_REPO" => "git@github.com:acme/ios.git",
             "BUILDKITE_PULL_REQUEST_REPO" => "https://github.com/acme/ios.git"
           }
         }}
      end)

      assert Buildkite.job_trusted?(account.id, workflow_job_id)
    end

    test "does not trust a fork's pull request", %{
      account: account,
      workflow_job_id: workflow_job_id
    } do
      stub(Client, :get_job, fn _installation, _uuid ->
        {:ok,
         %{
           "env" => %{
             "BUILDKITE_REPO" => "git@github.com:acme/ios.git",
             "BUILDKITE_PULL_REQUEST_REPO" => "https://github.com/someone-else/ios.git"
           }
         }}
      end)

      refute Buildkite.job_trusted?(account.id, workflow_job_id)
    end

    test "does not trust a job whose payload cannot be read", %{
      account: account,
      workflow_job_id: workflow_job_id
    } do
      stub(Client, :get_job, fn _installation, _uuid -> {:error, :not_found} end)

      refute Buildkite.job_trusted?(account.id, workflow_job_id)
    end
  end

  describe "conclusion_for/1" do
    test "maps an agent's exit status onto the lifecycle vocabulary" do
      assert Buildkite.conclusion_for(%{exit_status: 0, cancelled: false}) == "success"
      assert Buildkite.conclusion_for(%{exit_status: 1, cancelled: false}) == "failure"
      assert Buildkite.conclusion_for(%{exit_status: 0, cancelled: true}) == "cancelled"
    end
  end

  describe "upsert_installation/2" do
    test "rejects a token that is not a cluster agent token", %{account: account} do
      assert {:error, changeset} =
               Buildkite.upsert_installation(account.id, %{
                 organization_slug: "acme",
                 stack_key: "tuist-stack",
                 agent_token: "bkua_not_a_cluster_token"
               })

      assert "must be a Buildkite cluster agent token (starts with bkct_)" in errors_on(changeset).agent_token
    end

    test "rejects a stack key Buildkite would not accept", %{account: account} do
      assert {:error, changeset} =
               Buildkite.upsert_installation(account.id, %{
                 organization_slug: "acme",
                 stack_key: "not a valid key",
                 agent_token: "bkct_secret"
               })

      assert errors_on(changeset)[:stack_key]
    end
  end
end
