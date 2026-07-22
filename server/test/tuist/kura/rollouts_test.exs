defmodule Tuist.Kura.RolloutsTest do
  use TuistTestSupport.Cases.DataCase, async: true

  import Ecto.Query
  import Mimic

  alias Tuist.Accounts
  alias Tuist.Kura
  alias Tuist.Kura.Deployment
  alias Tuist.Kura.Provisioner
  alias Tuist.Kura.Rollout
  alias Tuist.Kura.Rollouts
  alias Tuist.Kura.RolloutServer
  alias Tuist.Kura.RolloutWaveAssignment
  alias Tuist.Kura.Server
  alias Tuist.Kura.Usage
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup :set_mimic_from_context

  @baseline_tag "0.5.2"
  @target_tag "0.6.0"

  setup do
    stub(Tuist.Kura.Rollouts.Notifier, :notify, fn _event, _rollout, _metadata -> :ok end)
    stub(Usage, :recent_request_counts_by_account, fn _account_ids, _days -> %{} end)
    stub(Tuist.Environment, :kura_runtime_image_tag, fn -> @target_tag end)
    stub(Tuist.Environment, :kura_canary_account_handles, fn -> [] end)
    stub(Tuist.Environment, :kura_rollout_expedite_tag, fn -> nil end)
    stub(Tuist.Environment, :kura_rollout_pacing, fn -> nil end)
    stub(Provisioner, :rollout_health, fn _server -> {:ok, healthy_health()} end)
    :ok
  end

  defp healthy_health(overrides \\ %{}) do
    Map.merge(
      %{
        ready: true,
        serving: true,
        generation_consistent: true,
        bootstrap_inflight_peers: 0,
        outbox_messages: 10,
        fd_timeout_count: 0,
        peer_connection_failures: 0,
        memory_pressure_state: 0,
        sampled_pods: 1,
        expected_pods: 1,
        sampled_at: DateTime.utc_now()
      },
      overrides
    )
  end

  defp create_active_server(_context \\ %{}) do
    user = AccountsFixtures.user_fixture()
    account = Accounts.get_account_from_user(user)

    {:ok, server} =
      Kura.create_server(%{account_id: account.id, region: "local-controller", image_tag: @baseline_tag})

    # Close the initial install deployment the way the reconciler's apply
    # path would: a server holds at most one open deployment, so the
    # rollout can only mint once the install has finished.
    close_open_deployments(server)

    {:ok, server} = Kura.activate_server(server, @baseline_tag)
    %{account: account, server: server}
  end

  defp close_open_deployments(server) do
    Deployment
    |> where([d], d.kura_server_id == ^server.id and d.status in [:pending, :running])
    |> Repo.all()
    |> Enum.each(fn deployment ->
      {:ok, deployment} =
        case deployment.status do
          :pending -> Kura.mark_running(deployment)
          :running -> {:ok, deployment}
        end

      {:ok, _} = Kura.mark_succeeded(deployment)
    end)
  end

  defp rollout_server(rollout, server) do
    Repo.get_by(RolloutServer, kura_rollout_id: rollout.id, kura_server_id: server.id)
  end

  defp back_date(rollout, field, seconds) do
    value = DateTime.utc_now() |> DateTime.add(-seconds, :second) |> DateTime.truncate(:second)

    {1, _} =
      Rollout
      |> where([r], r.id == ^rollout.id)
      |> Repo.update_all(set: [{field, value}])

    Repo.get!(Rollout, rollout.id)
  end

  describe "sync/0 in expedited mode" do
    test "mints an expedited rollout, fans out, and completes on convergence" do
      %{server: server} = create_active_server()

      assert :ok = Rollouts.sync()

      rollout = Rollouts.active_rollout()
      assert rollout.image_tag == @target_tag
      assert rollout.mode == :expedited
      assert rollout.status == :running
      assert rollout.baseline_image_tag == nil

      rollout_server = rollout_server(rollout, server)
      assert rollout_server.wave >= 0

      deployment = Repo.get!(Deployment, rollout_server.deployment_id)
      assert deployment.image_tag == @target_tag
      assert deployment.kura_rollout_id == rollout.id

      {:ok, _server} = Kura.activate_server(Repo.get!(Server, server.id), @target_tag)

      assert :ok = Rollouts.sync()
      assert Repo.get!(Rollout, rollout.id).status == :completed
    end

    test "a same-tag sync leaves a paused rollout untouched" do
      create_active_server()

      assert :ok = Rollouts.sync()
      rollout = Rollouts.active_rollout()
      {:ok, paused} = Rollouts.pause(rollout, "op@tuist.dev", "investigating")

      assert :ok = Rollouts.sync()

      reloaded = Repo.get!(Rollout, paused.id)
      assert reloaded.status == :paused
      assert Rollouts.active_rollout().id == paused.id
    end

    test "a tag change supersedes the active rollout and cancels its open deployments" do
      %{server: server} = create_active_server()

      assert :ok = Rollouts.sync()
      first = Rollouts.active_rollout()
      first_deployment = Repo.get!(Deployment, rollout_server(first, server).deployment_id)
      assert first_deployment.status == :pending

      stub(Tuist.Environment, :kura_runtime_image_tag, fn -> "0.7.0" end)
      assert :ok = Rollouts.sync()

      assert Repo.get!(Rollout, first.id).status == :superseded
      assert Repo.get!(Deployment, first_deployment.id).status == :cancelled

      second = Rollouts.active_rollout()
      assert second.image_tag == "0.7.0"
    end

    test "pauses on a terminal deployment failure" do
      %{server: server} = create_active_server()

      assert :ok = Rollouts.sync()
      rollout = Rollouts.active_rollout()
      deployment = Repo.get!(Deployment, rollout_server(rollout, server).deployment_id)
      {:ok, deployment} = Kura.mark_running(deployment)
      {:ok, _} = Kura.mark_failed(deployment, "node lost")

      assert :ok = Rollouts.sync()

      reloaded = Repo.get!(Rollout, rollout.id)
      assert reloaded.status == :paused
      assert reloaded.pause_reason == "deployment_failed"
    end
  end

  describe "sync/0 in progressive mode" do
    setup do
      stub(Tuist.Environment, :kura_rollout_pacing, fn -> "progressive" end)
      :ok
    end

    test "schedules the canary wave first and holds later waves behind the soak" do
      %{account: canary_account, server: canary_server} = create_active_server()
      %{server: customer_server} = create_active_server()

      stub(Tuist.Environment, :kura_canary_account_handles, fn -> [String.downcase(canary_account.name)] end)

      assert :ok = Rollouts.sync()

      rollout = Rollouts.active_rollout()
      assert rollout.mode == :progressive
      assert rollout.current_wave == 0

      assert Repo.get_by(RolloutWaveAssignment, kura_rollout_id: rollout.id, account_id: canary_account.id).wave == 0

      assert rollout_server(rollout, canary_server)
      refute rollout_server(rollout, customer_server)
    end

    test "completes a wave after convergence plus a continuously healthy soak" do
      %{account: canary_account, server: canary_server} = create_active_server()
      %{server: customer_server} = create_active_server()

      stub(Tuist.Environment, :kura_canary_account_handles, fn -> [String.downcase(canary_account.name)] end)

      assert :ok = Rollouts.sync()
      rollout = Rollouts.active_rollout()

      {:ok, _} = Kura.activate_server(Repo.get!(Server, canary_server.id), @target_tag)

      # Converged and healthy: the soak clock starts but the wave does not
      # complete yet.
      assert :ok = Rollouts.sync()
      rollout = Repo.get!(Rollout, rollout.id)
      assert rollout.current_wave == 0
      assert rollout.wave_healthy_since

      # After the canary soak has elapsed the wave completes and the next
      # wave schedules the customer account's server.
      rollout = back_date(rollout, :wave_healthy_since, 16 * 60)
      assert :ok = Rollouts.sync()

      rollout = Repo.get!(Rollout, rollout.id)
      assert rollout.current_wave == 1
      assert rollout_server(rollout, customer_server)
    end

    test "an empty canary wave advances immediately" do
      %{server: customer_server} = create_active_server()

      assert :ok = Rollouts.sync()

      rollout = Rollouts.active_rollout()
      assert rollout.current_wave == 1
      assert rollout_server(rollout, customer_server)
    end

    test "a failing gate resets the soak clock and the deadline pauses the rollout" do
      %{account: canary_account, server: canary_server} = create_active_server()

      stub(Tuist.Environment, :kura_canary_account_handles, fn -> [String.downcase(canary_account.name)] end)

      assert :ok = Rollouts.sync()
      rollout = Rollouts.active_rollout()

      {:ok, _} = Kura.activate_server(Repo.get!(Server, canary_server.id), @target_tag)
      assert :ok = Rollouts.sync()
      assert Repo.get!(Rollout, rollout.id).wave_healthy_since

      stub(Provisioner, :rollout_health, fn _server ->
        {:ok, healthy_health(%{serving: false})}
      end)

      assert :ok = Rollouts.sync()
      rollout = Repo.get!(Rollout, rollout.id)
      assert rollout.wave_healthy_since == nil
      assert rollout.status == :running

      rollout = back_date(rollout, :wave_started_at, 61 * 60)
      assert :ok = Rollouts.sync()

      rollout = Repo.get!(Rollout, rollout.id)
      assert rollout.status == :paused
      assert rollout.pause_reason == "wave_deadline_exceeded"
    end

    test "critical memory pressure pauses immediately" do
      %{account: canary_account, server: canary_server} = create_active_server()

      stub(Tuist.Environment, :kura_canary_account_handles, fn -> [String.downcase(canary_account.name)] end)

      assert :ok = Rollouts.sync()
      rollout = Rollouts.active_rollout()

      {:ok, _} = Kura.activate_server(Repo.get!(Server, canary_server.id), @target_tag)

      stub(Provisioner, :rollout_health, fn _server ->
        {:ok, healthy_health(%{memory_pressure_state: 2})}
      end)

      assert :ok = Rollouts.sync()

      rollout = Repo.get!(Rollout, rollout.id)
      assert rollout.status == :paused
      assert rollout.pause_reason == "memory_pressure_critical"
    end

    test "a baseline-unhealthy server is excluded from the soak but still must converge" do
      %{account: canary_account, server: canary_server} = create_active_server()

      stub(Tuist.Environment, :kura_canary_account_handles, fn -> [String.downcase(canary_account.name)] end)

      stub(Provisioner, :rollout_health, fn _server ->
        {:ok, healthy_health(%{ready: false, serving: false})}
      end)

      assert :ok = Rollouts.sync()
      rollout = Rollouts.active_rollout()

      rollout_server = rollout_server(rollout, canary_server)
      refute rollout_server.soak_eligible
      assert rollout_server.deployment_id

      # Unconverged: the wave cannot complete even though the sick server
      # is ungated.
      rollout = back_date(Repo.get!(Rollout, rollout.id), :wave_healthy_since, 16 * 60)
      assert :ok = Rollouts.sync()
      assert Repo.get!(Rollout, rollout.id).current_wave == 0
    end
  end

  describe "operator verbs" do
    setup do
      stub(Tuist.Environment, :kura_rollout_pacing, fn -> "progressive" end)
      :ok
    end

    test "resume re-attempts failed deployments with a fresh attempt" do
      %{account: canary_account, server: canary_server} = create_active_server()

      stub(Tuist.Environment, :kura_canary_account_handles, fn -> [String.downcase(canary_account.name)] end)

      assert :ok = Rollouts.sync()
      rollout = Rollouts.active_rollout()

      failed_deployment = Repo.get!(Deployment, rollout_server(rollout, canary_server).deployment_id)
      {:ok, failed_deployment} = Kura.mark_running(failed_deployment)
      {:ok, _} = Kura.mark_failed(failed_deployment, "bad storage class")

      assert :ok = Rollouts.sync()
      assert Repo.get!(Rollout, rollout.id).status == :paused

      {:ok, resumed} = Rollouts.resume(Repo.get!(Rollout, rollout.id), "op@tuist.dev", "storage class fixed")
      assert resumed.status == :running

      rollout_server = rollout_server(resumed, canary_server)
      assert rollout_server.attempt == 1
      assert rollout_server.deployment_id != failed_deployment.id
      assert Repo.get!(Deployment, rollout_server.deployment_id).status == :pending

      [event | _] = Rollouts.list_events(resumed)
      assert event.action == "resumed"
      assert event.actor == "op@tuist.dev"
    end

    test "expedite flips the mode, records the audit trail, and fans out the remainder" do
      %{account: canary_account, server: canary_server} = create_active_server()
      %{server: customer_server} = create_active_server()

      stub(Tuist.Environment, :kura_canary_account_handles, fn -> [String.downcase(canary_account.name)] end)

      assert :ok = Rollouts.sync()
      rollout = Rollouts.active_rollout()
      refute rollout_server(rollout, customer_server)

      {:ok, expedited} = Rollouts.expedite(rollout, "op@tuist.dev", "incident 123: outage math beats risk")
      assert expedited.mode == :expedited

      [event | _] = Rollouts.list_events(expedited)
      assert event.action == "expedited"
      assert event.actor == "op@tuist.dev"
      assert event.metadata["target_tag"] == @target_tag
      assert event.metadata["previously_completed"] == false

      assert :ok = Rollouts.sync()
      assert rollout_server(expedited, customer_server)
      assert rollout_server(expedited, canary_server)
    end

    test "abort cancels the rollout's open deployments" do
      %{account: canary_account, server: canary_server} = create_active_server()

      stub(Tuist.Environment, :kura_canary_account_handles, fn -> [String.downcase(canary_account.name)] end)

      assert :ok = Rollouts.sync()
      rollout = Rollouts.active_rollout()
      deployment = Repo.get!(Deployment, rollout_server(rollout, canary_server).deployment_id)

      {:ok, aborted} = Rollouts.abort(rollout, "op@tuist.dev", "wrong tag entirely")
      assert aborted.status == :aborted
      assert Repo.get!(Deployment, deployment.id).status == :cancelled
      assert Rollouts.active_rollout() == nil
    end

    test "manual pause requires a running rollout" do
      create_active_server()

      assert :ok = Rollouts.sync()
      rollout = Rollouts.active_rollout()

      {:ok, paused} = Rollouts.pause(rollout, "op@tuist.dev", "observed suspicious latency")
      assert paused.status == :paused
      assert {:error, {:not_pausable, :paused}} = Rollouts.pause(paused, "op@tuist.dev", "again")
    end
  end

  describe "provisioning_image_tag/2" do
    setup do
      stub(Tuist.Environment, :kura_rollout_pacing, fn -> "progressive" end)
      :ok
    end

    test "inherits the account's wave state during a progressive rollout" do
      %{account: canary_account, server: canary_server} = create_active_server()
      %{account: customer_account} = create_active_server()

      stub(Tuist.Environment, :kura_canary_account_handles, fn -> [String.downcase(canary_account.name)] end)
      stub(Tuist.FeatureFlags, :kura_rollout_orchestration_enabled?, fn -> true end)

      # No rollout yet: the configured default stands.
      assert Rollouts.provisioning_image_tag(customer_account.id, @target_tag) == @target_tag

      assert :ok = Rollouts.sync()
      rollout = Rollouts.active_rollout()

      # Rollout created from a fleet on the baseline: the first rollout has
      # no baseline recorded, so fresh servers fall back to the default.
      # Simulate a later rollout by stamping the baseline.
      {1, _} =
        Rollout
        |> where([r], r.id == ^rollout.id)
        |> Repo.update_all(set: [baseline_image_tag: @baseline_tag])

      # The customer account's wave has not completed: baseline.
      assert Rollouts.provisioning_image_tag(customer_account.id, @target_tag) == @baseline_tag

      # Complete the canary wave; the canary account's wave is now behind
      # the current wave, so its fresh servers take the target.
      {:ok, _} = Kura.activate_server(Repo.get!(Server, canary_server.id), @target_tag)
      assert :ok = Rollouts.sync()
      rollout = back_date(Repo.get!(Rollout, rollout.id), :wave_healthy_since, 16 * 60)
      assert :ok = Rollouts.sync()
      assert Repo.get!(Rollout, rollout.id).current_wave == 1

      assert Rollouts.provisioning_image_tag(canary_account.id, @target_tag) == @target_tag
      assert Rollouts.provisioning_image_tag(customer_account.id, @target_tag) == @baseline_tag
    end

    test "returns the default when orchestration is disabled" do
      %{account: account} = create_active_server()

      stub(Tuist.FeatureFlags, :kura_rollout_orchestration_enabled?, fn -> false end)

      assert Rollouts.provisioning_image_tag(account.id, @target_tag) == @target_tag
    end
  end

  describe "wave assignment" do
    test "splits non-canary accounts by usage ascending into 5/25/70 waves" do
      stub(Tuist.Environment, :kura_rollout_pacing, fn -> "progressive" end)

      %{account: canary_account} = create_active_server()
      contexts = for _index <- 1..4, do: create_active_server()

      [busiest | _rest] = accounts = Enum.map(contexts, & &1.account)

      stub(Tuist.Environment, :kura_canary_account_handles, fn -> [String.downcase(canary_account.name)] end)

      stub(Usage, :recent_request_counts_by_account, fn _ids, _days ->
        %{busiest.id => 1_000_000}
      end)

      assert :ok = Rollouts.sync()
      rollout = Rollouts.active_rollout()

      assignments =
        RolloutWaveAssignment
        |> where([w], w.kura_rollout_id == ^rollout.id)
        |> Repo.all()
        |> Map.new(&{&1.account_id, &1.wave})

      assert assignments[canary_account.id] == 0
      # The busiest account lands in the last wave.
      assert assignments[busiest.id] == 3
      # 4 non-canary accounts: wave 1 takes ceil(4 * 0.05) = 1, wave 2
      # takes ceil(4 * 0.25) = 1, the remainder lands in wave 3.
      waves = accounts |> Enum.map(&assignments[&1.id]) |> Enum.sort()
      assert waves == [1, 2, 3, 3]
    end
  end

  describe "rollout status endpoint payloads" do
    test "previously_completed?/1 reflects completed rollouts only" do
      create_active_server()

      refute Rollouts.previously_completed?(@target_tag)

      assert :ok = Rollouts.sync()
      rollout = Rollouts.active_rollout()
      {:ok, _} = Rollouts.abort(rollout, "op@tuist.dev", "nope")

      refute Rollouts.previously_completed?(@target_tag)
    end
  end
end
