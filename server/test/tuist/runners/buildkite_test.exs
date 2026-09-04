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
  alias Tuist.Runners.Buildkite.ReportToken
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

    stub(Client, :register_stack, fn _installation, stack_key, _queue_key, _metadata ->
      {:ok, %{"key" => stack_key}}
    end)

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

      expect(Client, :list_scheduled_jobs, fn _installation, _stack, ^queue_key, _limit ->
        {:ok, %{jobs: [job], dispatch_paused: false}}
      end)

      expect(Client, :reserve, fn _installation, _stack, uuids, _expiry ->
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

      stub(Client, :list_scheduled_jobs, fn _installation, _stack, _queue, _limit ->
        {:ok, %{jobs: [job], dispatch_paused: false}}
      end)

      stub(Client, :reserve, fn _installation, _stack, uuids, _expiry -> {:ok, uuids} end)

      assert {:ok, 1} = Buildkite.poll(installation)

      mapping = Repo.one(from(j in Job, where: j.job_uuid == ^job.job_uuid))
      assert mapping.workflow_job_id >= 1_000_000_000_000_000
    end

    test "leaves a paused queue alone", %{installation: installation, queue_key: queue_key} do
      stub(Client, :list_scheduled_jobs, fn _installation, _stack, ^queue_key, _limit ->
        {:ok, %{jobs: [scheduled_job()], dispatch_paused: true}}
      end)

      reject(&Client.reserve/4)

      assert {:ok, 0} = Buildkite.poll(installation)
    end

    test "does not queue a job another stack reserved first", %{
      installation: installation,
      queue_key: queue_key
    } do
      job = scheduled_job(%{queue_key: queue_key})

      stub(Client, :list_scheduled_jobs, fn _installation, _stack, _queue, _limit ->
        {:ok, %{jobs: [job], dispatch_paused: false}}
      end)

      stub(Client, :reserve, fn _installation, _stack, _uuids, _expiry -> {:ok, []} end)

      assert {:ok, 0} = Buildkite.poll(installation)
      assert Repo.aggregate(from(j in Job, where: j.job_uuid == ^job.job_uuid), :count) == 0
    end

    test "does not re-queue a job it already holds", %{
      installation: installation,
      queue_key: queue_key
    } do
      job = scheduled_job(%{queue_key: queue_key})

      stub(Client, :list_scheduled_jobs, fn _installation, _stack, _queue, _limit ->
        {:ok, %{jobs: [job], dispatch_paused: false}}
      end)

      stub(Client, :reserve, fn _installation, _stack, uuids, _expiry -> {:ok, uuids} end)

      assert {:ok, 1} = Buildkite.poll(installation)
      assert {:ok, 0} = Buildkite.poll(installation)

      assert Repo.aggregate(from(j in Job, where: j.job_uuid == ^job.job_uuid), :count) == 1
    end

    test "registers the stack on the first 404 and retries the list", %{
      installation: installation,
      queue_key: queue_key
    } do
      job = scheduled_job(%{queue_key: queue_key})
      test_pid = self()
      expected_stack = Buildkite.stack_key_for(installation, queue_key)

      # Buildkite answers nothing for an unregistered key, so a brand new
      # queue always 404s once before it can be polled.
      Mimic.expect(Client, :list_scheduled_jobs, fn _installation, ^expected_stack, ^queue_key, _limit ->
        {:error, :not_found}
      end)

      Mimic.expect(Client, :register_stack, fn _installation, ^expected_stack, ^queue_key, metadata ->
        send(test_pid, {:registered, metadata})
        {:ok, %{"key" => expected_stack}}
      end)

      Mimic.expect(Client, :list_scheduled_jobs, fn _installation, ^expected_stack, ^queue_key, _limit ->
        {:ok, %{jobs: [job], dispatch_paused: false}}
      end)

      stub(Client, :reserve, fn _installation, _stack, uuids, _expiry -> {:ok, uuids} end)

      assert {:ok, 1} = Buildkite.poll(installation)
      assert_received {:registered, metadata}
      assert metadata["tuist_account"]
    end

    test "skips a profile whose Buildkite queue does not exist", %{installation: installation} do
      # A 404 that survives registration means the queue is not there.
      # Profiles are ours and queues are the customer's, so any profile
      # they have not made a matching queue for lands here on every pass.
      # It must not fail the installation or stop the queues that do
      # exist: staging had exactly this shape, and treating it as fatal
      # stamped an error on the account and could starve the working
      # queues depending on profile ordering.
      stub(Client, :list_scheduled_jobs, fn _installation, _stack, _queue, _limit ->
        {:error, :not_found}
      end)

      stub(Client, :register_stack, fn _installation, stack, _queue, _metadata ->
        {:ok, %{"key" => stack}}
      end)

      assert {:ok, 0} = Buildkite.poll(installation)
    end

    test "keeps polling the other queues when one is absent", %{
      installation: installation,
      queue_key: queue_key
    } do
      absent = "tuist-staging-nonexistent"
      job = scheduled_job(%{queue_key: queue_key})

      stub(Profiles, :list_for_account, fn _account ->
        [
          %Profile{name: "nonexistent", platform: :macos, vcpus: 4, memory_gb: 16},
          %Profile{
            name: String.replace_prefix(queue_key, Profile.prefix(), ""),
            platform: :macos,
            vcpus: 4,
            memory_gb: 16
          }
        ]
      end)

      stub(Dispatch, :resolve_dispatch_target, fn _account, [key] ->
        if key == queue_key do
          {:ok,
           %{
             pool_name: "pool-macos",
             requested_dispatch_label: queue_key,
             platform: :macos,
             vcpus: 4,
             memory_gb: 16
           }}
        else
          {:error, :no_matching_profile}
        end
      end)

      stub(Client, :list_scheduled_jobs, fn _installation, _stack, key, _limit ->
        if key == queue_key do
          {:ok, %{jobs: [job], dispatch_paused: false}}
        else
          {:error, :not_found}
        end
      end)

      stub(Client, :register_stack, fn _installation, stack, _queue, _metadata ->
        {:ok, %{"key" => stack}}
      end)

      stub(Client, :reserve, fn _installation, _stack, uuids, _expiry -> {:ok, uuids} end)

      # The absent queue is listed first, so a fatal reading of its 404
      # would starve the working queue behind it.
      assert {:ok, 1} = Buildkite.poll(installation)
      assert absent != queue_key
    end

    test "re-enqueues a job whose mapping row exists without a lifecycle row", %{
      installation: installation,
      account: account,
      queue_key: queue_key
    } do
      # Staging blackholed two real jobs this way. The mapping row is
      # written before the lifecycle row, so a half-written job used to be
      # filtered out as "known" on every later pass while it sat scheduled
      # on Buildkite forever. Known must mean "has a lifecycle row".
      job = scheduled_job(%{queue_key: queue_key})

      {:ok, orphan} =
        %Job{}
        |> Job.changeset(%{
          job_uuid: job.job_uuid,
          account_id: account.id,
          organization_slug: "acme",
          queue_key: queue_key
        })
        |> Repo.insert(returning: true)

      assert is_nil(Repo.get(WorkflowJob, orphan.workflow_job_id))

      stub(Client, :list_scheduled_jobs, fn _installation, _stack, _queue, _limit ->
        {:ok, %{jobs: [job], dispatch_paused: false}}
      end)

      stub(Client, :reserve, fn _installation, _stack, uuids, _expiry -> {:ok, uuids} end)

      assert {:ok, 1} = Buildkite.poll(installation)

      lifecycle = Repo.get(WorkflowJob, orphan.workflow_job_id)
      assert lifecycle.status == "queued"
      assert lifecycle.provider == "buildkite"
    end

    test "reuses the existing surrogate id rather than minting a second one", %{
      installation: installation,
      queue_key: queue_key
    } do
      # The id comes from a database default, so an insert that hits
      # ON CONFLICT DO NOTHING returns no row to read it from. Reading the
      # mapping back keeps one job on one id across passes.
      job = scheduled_job(%{queue_key: queue_key})

      stub(Client, :list_scheduled_jobs, fn _installation, _stack, _queue, _limit ->
        {:ok, %{jobs: [job], dispatch_paused: false}}
      end)

      stub(Client, :reserve, fn _installation, _stack, uuids, _expiry -> {:ok, uuids} end)

      assert {:ok, 1} = Buildkite.poll(installation)
      first = Repo.one(from(j in Job, where: j.job_uuid == ^job.job_uuid)).workflow_job_id

      # Second pass: the lifecycle row now exists, so it is correctly skipped.
      assert {:ok, 0} = Buildkite.poll(installation)

      assert Repo.aggregate(from(j in Job, where: j.job_uuid == ^job.job_uuid), :count) == 1
      assert Repo.one(from(j in Job, where: j.job_uuid == ^job.job_uuid)).workflow_job_id == first
    end

    test "enqueues a job whose timestamp carries only millisecond precision", %{
      installation: installation,
      queue_key: queue_key
    } do
      # Buildkite stamps milliseconds. `runner_workflow_jobs.enqueued_at`
      # is `:utc_datetime_usec`, and `insert_all` dumps without casting,
      # so a 3-digit timestamp raised ArgumentError *after* the pass had
      # already reserved the job on Buildkite. Oban discarded the crash
      # and the job sat reserved and invisible to every stack until its
      # reservation lapsed an hour later. This is that exact shape.
      {:ok, millisecond_precision, _} = DateTime.from_iso8601("2026-09-04T18:20:36.542Z")
      assert millisecond_precision.microsecond == {542_000, 3}

      job = scheduled_job(%{queue_key: queue_key, scheduled_at: millisecond_precision})

      stub(Client, :list_scheduled_jobs, fn _installation, _stack, _queue, _limit ->
        {:ok, %{jobs: [job], dispatch_paused: false}}
      end)

      stub(Client, :reserve, fn _installation, _stack, uuids, _expiry -> {:ok, uuids} end)

      assert {:ok, 1} = Buildkite.poll(installation)

      mapping = Repo.one(from(j in Job, where: j.job_uuid == ^job.job_uuid))
      lifecycle = Repo.get(WorkflowJob, mapping.workflow_job_id)
      assert lifecycle.status == "queued"
      assert DateTime.compare(lifecycle.enqueued_at, millisecond_precision) == :eq
    end

    test "stops the pass when the agent token is rejected", %{installation: installation} do
      stub(Client, :list_scheduled_jobs, fn _installation, _stack, _queue, _limit ->
        {:error, :unauthorized}
      end)

      assert {:error, :unauthorized} = Buildkite.poll(installation)
    end

    test "is a no-op when the account's allowance is exhausted", %{installation: installation} do
      stub(Allowance, :exhausted?, fn _account -> true end)
      reject(&Client.list_scheduled_jobs/4)

      assert {:error, :allowance_exhausted} = Buildkite.poll(installation)
    end

    test "is a no-op when runners are disabled for the account", %{installation: installation} do
      stub(FeatureFlags, :runners_enabled?, fn _account -> false end)
      reject(&Client.list_scheduled_jobs/4)

      assert {:error, :runners_disabled} = Buildkite.poll(installation)
    end
  end

  describe "poll/1 reservation renewal" do
    setup %{installation: installation, queue_key: queue_key} do
      job = scheduled_job(%{queue_key: queue_key})

      stub(Client, :list_scheduled_jobs, fn _installation, _stack, _queue, _limit ->
        {:ok, %{jobs: [job], dispatch_paused: false}}
      end)

      stub(Client, :reserve, fn _installation, _stack, uuids, _expiry -> {:ok, uuids} end)
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
      stub(Client, :list_scheduled_jobs, fn _installation, _stack, _queue, _limit ->
        {:ok, %{jobs: [], dispatch_paused: false}}
      end)

      expect(Client, :reserve, fn _installation, _stack, uuids, _expiry ->
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
      stub(Client, :list_scheduled_jobs, fn _installation, _stack, _queue, _limit ->
        {:ok, %{jobs: [], dispatch_paused: false}}
      end)

      stub(Client, :reserve, fn _installation, _stack, _uuids, _expiry -> {:ok, []} end)

      assert {:ok, 0} = Buildkite.poll(installation)

      mapping = Repo.one(from(j in Job, where: j.job_uuid == ^job.job_uuid))
      assert Repo.get(WorkflowJob, mapping.workflow_job_id).status == "cancelled"
    end

    test "requeues a job whose runner died between dispatch and acquisition", %{
      installation: installation,
      job: job
    } do
      # The runner took the job and died before its agent acquired it.
      # Nothing else can recover this: the claim is deleted without a
      # requeue, the orphan sweeper resolves through the GitHub API which
      # knows nothing about a Buildkite job, and the job is filtered out
      # of every later poll because a lifecycle row exists for it. Without
      # a Buildkite-side recovery the customer's job is stranded forever.
      mapping = Repo.one(from(j in Job, where: j.job_uuid == ^job.job_uuid))
      running(mapping.workflow_job_id)

      stub(Client, :list_scheduled_jobs, fn _installation, _stack, _queue, _limit ->
        {:ok, %{jobs: [], dispatch_paused: false}}
      end)

      stub(Client, :reserve, fn _installation, _stack, uuids, _expiry -> {:ok, uuids} end)

      assert {:ok, 0} = Buildkite.poll(installation)

      row = Repo.get(WorkflowJob, mapping.workflow_job_id)
      assert row.status == "queued"
      assert is_nil(row.pod_name)
      assert is_nil(row.claimed_at)
    end

    test "leaves a dispatched job alone when Buildkite refuses to re-reserve it", %{
      installation: installation,
      job: job
    } do
      # A refusal is ambiguous for a dispatched job: Buildkite withholds a
      # job that an agent has already acquired, so the most likely reading
      # is that it is running right now. Cancelling it here would destroy a
      # live build's record.
      mapping = Repo.one(from(j in Job, where: j.job_uuid == ^job.job_uuid))
      running(mapping.workflow_job_id)

      stub(Client, :list_scheduled_jobs, fn _installation, _stack, _queue, _limit ->
        {:ok, %{jobs: [], dispatch_paused: false}}
      end)

      stub(Client, :reserve, fn _installation, _stack, _uuids, _expiry -> {:ok, []} end)

      assert {:ok, 0} = Buildkite.poll(installation)

      assert Repo.get(WorkflowJob, mapping.workflow_job_id).status == "running"
    end

    defp running(workflow_job_id) do
      Repo.update_all(
        from(w in WorkflowJob, where: w.workflow_job_id == ^workflow_job_id),
        set: [
          status: "running",
          pod_name: "tuist-runner-pod-1",
          claimed_at: DateTime.truncate(DateTime.utc_now(), :second)
        ]
      )
    end
  end

  describe "job_trusted?/2" do
    setup %{installation: installation, account: account, queue_key: queue_key} do
      job = scheduled_job(%{queue_key: queue_key})

      stub(Client, :list_scheduled_jobs, fn _installation, _stack, _queue, _limit ->
        {:ok, %{jobs: [job], dispatch_paused: false}}
      end)

      stub(Client, :reserve, fn _installation, _stack, uuids, _expiry -> {:ok, uuids} end)
      assert {:ok, 1} = Buildkite.poll(installation)

      mapping = Repo.one(from(j in Job, where: j.job_uuid == ^job.job_uuid))
      %{account: account, workflow_job_id: mapping.workflow_job_id}
    end

    test "trusts a job with no pull-request repository", %{
      account: account,
      workflow_job_id: workflow_job_id
    } do
      stub(Client, :get_job, fn _installation, _stack, _uuid ->
        {:ok, %{"env" => %{"BUILDKITE_REPO" => "git@github.com:acme/ios.git"}}}
      end)

      assert Buildkite.job_trusted?(account.id, workflow_job_id)
    end

    test "trusts a same-repository pull request across remote spellings", %{
      account: account,
      workflow_job_id: workflow_job_id
    } do
      stub(Client, :get_job, fn _installation, _stack, _uuid ->
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
      stub(Client, :get_job, fn _installation, _stack, _uuid ->
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
      stub(Client, :get_job, fn _installation, _stack, _uuid -> {:error, :not_found} end)

      refute Buildkite.job_trusted?(account.id, workflow_job_id)
    end
  end

  describe "mint_acquisition/2" do
    setup %{installation: installation, account: account, queue_key: queue_key} do
      job = scheduled_job(%{queue_key: queue_key})

      stub(Client, :list_scheduled_jobs, fn _installation, _stack, _queue, _limit ->
        {:ok, %{jobs: [job], dispatch_paused: false}}
      end)

      stub(Client, :reserve, fn _installation, _stack, uuids, _expiry -> {:ok, uuids} end)
      assert {:ok, 1} = Buildkite.poll(installation)

      mapping = Repo.one(from(j in Job, where: j.job_uuid == ^job.job_uuid))
      %{account: account, workflow_job_id: mapping.workflow_job_id, job_uuid: job.job_uuid}
    end

    test "returns the acquisition token and a report credential for the job", %{
      account: account,
      workflow_job_id: workflow_job_id,
      job_uuid: job_uuid
    } do
      expect(Client, :issue_acquisition_token, fn _installation, _stack, ^job_uuid, _lifetime ->
        {:ok, %{token: "bkjat_opaque", expires_at: nil}}
      end)

      assert {:ok, acquisition} = Buildkite.mint_acquisition(account.id, workflow_job_id)

      assert acquisition.token == "bkjat_opaque"
      assert acquisition.job_uuid == job_uuid

      # The job reports its own log and outcome, so it needs a credential
      # it can carry. This one is scoped to the job rather than the
      # machine, which is what lets the Linux fleet — whose job container
      # holds no ServiceAccount token — use the same path.
      assert {:ok, %{workflow_job_id: ^workflow_job_id}} =
               ReportToken.verify(acquisition.report_token)
    end

    test "fails when Buildkite declines to issue a token", %{
      account: account,
      workflow_job_id: workflow_job_id
    } do
      stub(Client, :issue_acquisition_token, fn _installation, _stack, _uuid, _lifetime ->
        {:error, :not_issued}
      end)

      assert {:error, :not_issued} = Buildkite.mint_acquisition(account.id, workflow_job_id)
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
