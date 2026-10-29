defmodule Tuist.Runners.BitriseTest do
  use TuistTestSupport.Cases.DataCase, async: true

  import Ecto.Query
  import Mimic

  alias Tuist.FeatureFlags
  alias Tuist.Repo
  alias Tuist.Runners.Allowance
  alias Tuist.Runners.Bitrise
  alias Tuist.Runners.Bitrise.Build
  alias Tuist.Runners.Bitrise.Client
  alias Tuist.Runners.Bitrise.ReportToken
  alias Tuist.Runners.Catalog
  alias Tuist.Runners.Dispatch
  alias Tuist.Runners.Profile
  alias Tuist.Runners.Profiles
  alias Tuist.Runners.RunnerSession
  alias Tuist.Runners.RunnerSessions
  alias Tuist.Runners.WorkflowJob
  alias TuistTestSupport.Fixtures.AccountsFixtures

  @stack "agent-pool-ios"

  setup :verify_on_exit!

  setup do
    stub(Catalog, :default_xcode_version, fn -> nil end)
    stub(FeatureFlags, :runners_enabled?, fn _account -> true end)
    stub(Allowance, :exhausted?, fn _account -> false end)

    %{account: account} =
      AccountsFixtures.organization_fixture(
        name: "bitrise-org-#{System.unique_integer([:positive])}",
        preload: [:account]
      )

    [profile] = Profiles.list_for_account(account)
    label = Profile.dispatch_label(profile)

    stub(Dispatch, :resolve_dispatch_target, fn _account, [^label] ->
      {:ok, %{pool_name: "pool-macos", requested_dispatch_label: label, platform: :macos, vcpus: 6, memory_gb: 14}}
    end)

    {:ok, connection} = Bitrise.upsert_connection(account.id, %{workspace_slug: "n26-workspace", api_token: "secret"})

    {:ok, _pool} =
      Bitrise.save_pool(account.id, %{stack_identifier: @stack, profile_label: label, intro_secret: "intro"})

    %{account: account, connection: connection, label: label}
  end

  defp remote_build(overrides \\ %{}) do
    Map.merge(
      %{
        build_slug: "build-#{System.unique_integer([:positive])}",
        app_slug: "app-ios",
        app_title: "ios-app",
        stack_identifier: @stack,
        build_number: 7,
        status: 0,
        abort_reason: nil,
        branch: "main",
        commit_hash: "abc123",
        triggered_workflow: "primary",
        triggered_at: DateTime.utc_now(),
        started_on_worker_at: nil,
        finished_at: nil
      },
      overrides
    )
  end

  defp lifecycle(build_slug) do
    Repo.one(
      from(w in WorkflowJob,
        join: b in Build,
        on: b.workflow_job_id == w.workflow_job_id,
        where: b.build_slug == ^build_slug
      )
    )
  end

  describe "poll/1" do
    test "queues builds waiting on a connected pool", %{connection: connection, account: account, label: label} do
      waiting = remote_build()
      started = remote_build(%{started_on_worker_at: DateTime.utc_now()})
      elsewhere = remote_build(%{stack_identifier: "osx-xcode-26.0.x"})

      stub(Client, :list_unfinished_builds, fn _connection -> {:ok, [waiting, started, elsewhere]} end)

      assert {:ok, 1} = Bitrise.poll(connection)

      row = lifecycle(waiting.build_slug)
      assert row.provider == "bitrise"
      assert row.status == "queued"
      assert row.account_id == account.id
      assert row.fleet_name == "pool-macos"
      assert row.requested_dispatch_label == label
      assert row.workflow_job_id >= 3_000_000_000_000_000
      assert row.head_branch == "main"
      assert row.workflow_name == "primary"

      refute lifecycle(started.build_slug)
      refute lifecycle(elsewhere.build_slug)
    end

    test "does not queue a build twice", %{connection: connection} do
      waiting = remote_build()
      stub(Client, :list_unfinished_builds, fn _connection -> {:ok, [waiting]} end)

      assert {:ok, 1} = Bitrise.poll(connection)
      assert {:ok, 0} = Bitrise.poll(connection)
      assert Repo.aggregate(from(b in Build, where: b.build_slug == ^waiting.build_slug), :count) == 1
    end

    test "completes a finished build it ran with Bitrise's window", %{connection: connection, account: account} do
      waiting = remote_build()
      stub(Client, :list_unfinished_builds, fn _connection -> {:ok, [waiting]} end)
      assert {:ok, 1} = Bitrise.poll(connection)

      build = Repo.get_by!(Build, build_slug: waiting.build_slug)
      started_at = DateTime.add(DateTime.utc_now(), -600, :second)
      finished_at = DateTime.add(DateTime.utc_now(), -60, :second)

      {:ok, _session} =
        RunnerSessions.open(%{
          workflow_job_id: build.workflow_job_id,
          account_id: account.id,
          fleet_name: "pool-macos",
          platform: :macos,
          vcpus: 6,
          memory_gb: 14,
          pod_name: "pod-bitrise-1",
          runner_name: "runner-bitrise-1",
          started_at: started_at
        })

      build |> Ecto.Changeset.change(runner_name: "runner-bitrise-1") |> Repo.update!()

      stub(Client, :list_unfinished_builds, fn _connection -> {:ok, []} end)

      expect(Client, :get_build, fn _connection, "app-ios", slug ->
        assert slug == waiting.build_slug
        {:ok, remote_build(%{build_slug: slug, status: 2, started_on_worker_at: started_at, finished_at: finished_at})}
      end)

      assert {:ok, 0} = Bitrise.poll(connection)

      row = lifecycle(waiting.build_slug)
      assert row.status == "completed"
      assert row.conclusion == "failure"

      session = Repo.one(from(s in RunnerSession, where: s.runner_name == "runner-bitrise-1"))
      assert session.executed_workflow_job_id == build.workflow_job_id
      assert DateTime.compare(session.job_started_at, started_at) == :eq
      assert DateTime.compare(session.job_ended_at, finished_at) == :eq
    end

    test "leaves a build whose read failed for the next pass", %{connection: connection} do
      waiting = remote_build()
      stub(Client, :list_unfinished_builds, fn _connection -> {:ok, [waiting]} end)
      assert {:ok, 1} = Bitrise.poll(connection)

      stub(Client, :list_unfinished_builds, fn _connection -> {:ok, []} end)
      stub(Client, :get_build, fn _connection, _app, _slug -> {:error, {:transport, :timeout}} end)

      assert {:ok, 0} = Bitrise.poll(connection)
      assert lifecycle(waiting.build_slug).status == "queued"
    end

    test "settles finished builds but queues nothing while runners are disabled", %{connection: connection} do
      waiting = remote_build()
      stub(Client, :list_unfinished_builds, fn _connection -> {:ok, [waiting]} end)
      assert {:ok, 1} = Bitrise.poll(connection)

      cancelled_while_queued = remote_build()
      stub(FeatureFlags, :runners_enabled?, fn _account -> false end)
      stub(Client, :list_unfinished_builds, fn _connection -> {:ok, [cancelled_while_queued]} end)

      stub(Client, :get_build, fn _connection, _app, slug ->
        {:ok, remote_build(%{build_slug: slug, status: 3})}
      end)

      assert {:error, :runners_disabled} = Bitrise.poll(connection)
      assert lifecycle(waiting.build_slug).conclusion == "cancelled"
      refute lifecycle(cancelled_while_queued.build_slug)
    end

    test "reports a connection with no pools", %{account: account, connection: connection} do
      [pool] = Bitrise.list_pools(account.id)
      :ok = Bitrise.delete_pool(account.id, pool.id)

      assert {:error, :no_pools} = Bitrise.poll(connection)
    end

    test "stops the pass when the API token is rejected", %{connection: connection} do
      stub(Client, :list_unfinished_builds, fn _connection -> {:error, :unauthorized} end)

      assert {:error, :unauthorized} = Bitrise.poll(connection)
    end
  end

  describe "mint_acquisition/2" do
    test "returns the pool's intro secret and a report token", %{connection: connection, account: account} do
      waiting = remote_build()
      stub(Client, :list_unfinished_builds, fn _connection -> {:ok, [waiting]} end)
      assert {:ok, 1} = Bitrise.poll(connection)
      build = Repo.get_by!(Build, build_slug: waiting.build_slug)

      assert {:ok, %{intro_secret: "intro", report_token: token}} =
               Bitrise.mint_acquisition(account.id, build.workflow_job_id)

      assert {:ok, %{workflow_job_id: id, account_id: account_id}} = ReportToken.verify(token)
      assert id == build.workflow_job_id
      assert account_id == account.id
    end

    test "fails for another account's build", %{connection: connection} do
      waiting = remote_build()
      stub(Client, :list_unfinished_builds, fn _connection -> {:ok, [waiting]} end)
      assert {:ok, 1} = Bitrise.poll(connection)
      build = Repo.get_by!(Build, build_slug: waiting.build_slug)

      assert {:error, :not_found} = Bitrise.mint_acquisition(build.account_id + 1, build.workflow_job_id)
    end
  end

  describe "record_build_started/3" do
    setup %{connection: connection, account: account} do
      claimed = remote_build()
      stub(Client, :list_unfinished_builds, fn _connection -> {:ok, [claimed]} end)
      assert {:ok, 1} = Bitrise.poll(connection)
      build = Repo.get_by!(Build, build_slug: claimed.build_slug)

      {:ok, _session} =
        RunnerSessions.open(%{
          workflow_job_id: build.workflow_job_id,
          account_id: account.id,
          fleet_name: "pool-macos",
          platform: :macos,
          vcpus: 6,
          memory_gb: 14,
          pod_name: "pod-bitrise-start",
          runner_name: "runner-bitrise-start",
          started_at: DateTime.utc_now()
        })

      %{claimed: %{workflow_job_id: build.workflow_job_id, account_id: account.id}, build: build}
    end

    test "binds the claimed build when the agent took it", %{claimed: claimed, build: build, account: account} do
      account_id = account.id
      workflow_job_id = build.workflow_job_id

      expect(Dispatch, :record_execution, fn "runner-bitrise-start", ^workflow_job_id, ^account_id ->
        {:ok, :matched}
      end)

      assert :ok = Bitrise.record_build_started(claimed, build.build_slug, build.app_slug)
      assert Repo.get!(Build, workflow_job_id).runner_name == "runner-bitrise-start"
    end

    test "queues and binds a build no poll has seen yet", %{claimed: claimed, account: account} do
      account_id = account.id
      unseen = remote_build(%{started_on_worker_at: DateTime.utc_now()})

      expect(Client, :get_build, fn _connection, "app-ios", slug ->
        assert slug == unseen.build_slug
        {:ok, unseen}
      end)

      expect(Dispatch, :record_execution, fn "runner-bitrise-start", workflow_job_id, ^account_id ->
        assert workflow_job_id == Repo.get_by!(Build, build_slug: unseen.build_slug).workflow_job_id
        {:ok, :mismatch}
      end)

      assert :ok = Bitrise.record_build_started(claimed, unseen.build_slug, "app-ios")
      assert lifecycle(unseen.build_slug).provider == "bitrise"
    end

    test "refuses a build on a stack the account did not connect", %{claimed: claimed} do
      foreign = remote_build(%{stack_identifier: "osx-xcode-26.0.x"})
      stub(Client, :get_build, fn _connection, _app, _slug -> {:ok, foreign} end)
      reject(Dispatch, :record_execution, 3)

      assert {:error, :invalid_build} = Bitrise.record_build_started(claimed, foreign.build_slug, "app-ios")
      refute Repo.get_by(Build, build_slug: foreign.build_slug)
    end
  end

  describe "orphan_status/1" do
    setup %{connection: connection, account: account} do
      waiting = remote_build()
      stub(Client, :list_unfinished_builds, fn _connection -> {:ok, [waiting]} end)
      assert {:ok, 1} = Bitrise.poll(connection)
      build = Repo.get_by!(Build, build_slug: waiting.build_slug)

      %{orphan: %{workflow_job_id: build.workflow_job_id, account_id: account.id}}
    end

    test "folds Bitrise's build status into the sweep's vocabulary", %{orphan: orphan} do
      stub(Client, :get_build, fn _connection, _app, slug -> {:ok, remote_build(%{build_slug: slug})} end)
      assert {:ok, {"queued", ""}} = Bitrise.orphan_status(orphan)

      stub(Client, :get_build, fn _connection, _app, slug ->
        {:ok, remote_build(%{build_slug: slug, started_on_worker_at: DateTime.utc_now()})}
      end)

      assert {:ok, {"in_progress", ""}} = Bitrise.orphan_status(orphan)

      stub(Client, :get_build, fn _connection, _app, slug -> {:ok, remote_build(%{build_slug: slug, status: 1})} end)
      assert {:ok, {"completed", "success"}} = Bitrise.orphan_status(orphan)

      stub(Client, :get_build, fn _connection, _app, _slug -> {:error, :not_found} end)
      assert {:ok, {"completed", ""}} = Bitrise.orphan_status(orphan)
    end
  end

  describe "save_pool/2" do
    test "refuses a profile the account does not have", %{account: account} do
      assert {:error, :unknown_profile} =
               Bitrise.save_pool(account.id, %{stack_identifier: "other", profile_label: "missing", intro_secret: "x"})
    end

    test "replaces the pool already bound to a stack", %{account: account, label: label} do
      {:ok, _pool} =
        Bitrise.save_pool(account.id, %{stack_identifier: @stack, profile_label: label, intro_secret: "rotated"})

      assert [%{intro_secret: "rotated"}] = Bitrise.list_pools(account.id)
    end
  end
end
