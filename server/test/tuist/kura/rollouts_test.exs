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
    stub(Tuist.Environment, :kura_available_region_ids, fn -> ["local-controller"] end)
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
        ring_consistent: true,
        backfilling_peers: 0,
        backfill_degraded: false,
        backfill_budget_exhausted_peers: 0,
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
      # No previous rollout to chain from, so the baseline is read off the
      # fleet — which is still on the pre-rollout image at creation.
      assert rollout.baseline_image_tag == @baseline_tag

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

    test "a server with an open install deployment does not abort the tick" do
      # The rollout mints deployments while holding the rollout row lock, and
      # `Kura.create_deployment/3` rolls back when the server already has one
      # open. Without a savepoint that rollback aborts the outer transaction
      # and every later step of the reconcile tick raises, so this server is
      # left deliberately `:provisioning` with its install deployment open.
      user = AccountsFixtures.user_fixture()
      account = Accounts.get_account_from_user(user)

      {:ok, server} =
        Kura.create_server(%{account_id: account.id, region: "local-controller", image_tag: @baseline_tag})

      assert Repo.get_by(Deployment, kura_server_id: server.id).status == :pending

      assert :ok = Rollouts.sync()

      # Scoped with no deployment of its own; `mint_missing_deployments/1`
      # picks it up once the install closes.
      rollout = Rollouts.active_rollout()
      rollout_server = rollout_server(rollout, server)
      assert rollout_server
      assert is_nil(rollout_server.deployment_id)
    end

    test "servers in retired regions are not scoped into the rollout" do
      %{server: server} = create_active_server()

      # The region catalog no longer lists the server's region: the
      # control plane cannot deploy to it, so it must not hold waves open.
      stub(Tuist.Environment, :kura_available_region_ids, fn -> ["some-other-region"] end)

      assert :ok = Rollouts.sync()

      # Nothing is in scope, so the rollout completes immediately — and
      # the retired-region server was never scoped.
      rollout = Rollouts.latest_rollout()
      assert rollout.status == :completed
      refute rollout_server(rollout, server)
    end

    test "abort cancels adopted deployments, not only rollout-minted ones" do
      create_active_server()

      assert :ok = Rollouts.sync()
      rollout = Rollouts.active_rollout()

      # A server created mid-rollout provisions straight onto the target;
      # its initial install deployment stays open and the rollout adopts
      # it instead of double-deploying.
      user = AccountsFixtures.user_fixture()
      account = Accounts.get_account_from_user(user)

      {:ok, adopted_server} =
        Kura.create_server(%{account_id: account.id, region: "local-controller", image_tag: @target_tag})

      assert :ok = Rollouts.sync()

      adopted_rollout_server = rollout_server(rollout, adopted_server)
      adopted_deployment = Repo.get!(Deployment, adopted_rollout_server.deployment_id)
      assert adopted_deployment.kura_rollout_id == nil
      assert adopted_deployment.status == :pending

      {:ok, _} = Rollouts.abort(rollout, "op@tuist.dev", "wrong tag")

      assert Repo.get!(Deployment, adopted_deployment.id).status == :cancelled
    end

    test "a paused rollout pins fresh servers to the baseline even in expedited mode" do
      %{account: account} = create_active_server()

      assert :ok = Rollouts.sync()
      rollout = Rollouts.active_rollout()
      assert rollout.mode == :expedited

      {1, _} =
        Rollout
        |> where([r], r.id == ^rollout.id)
        |> Repo.update_all(set: [baseline_image_tag: @baseline_tag])

      stub(Tuist.FeatureFlags, :kura_rollout_orchestration_enabled?, fn -> true end)

      # Running expedited: fan-out intent, fresh servers take the target.
      assert Rollouts.provisioning_image_tag(account.id, @target_tag) == @target_tag

      {:ok, _} = Rollouts.pause(Repo.get!(Rollout, rollout.id), "op@tuist.dev", "suspect")

      # Paused: the target is suspect; fresh servers stay on the baseline.
      assert Rollouts.provisioning_image_tag(account.id, @target_tag) == @baseline_tag
    end

    test "critical memory pressure pauses an expedited rollout" do
      %{server: server} = create_active_server()

      assert :ok = Rollouts.sync()
      rollout = Rollouts.active_rollout()
      assert rollout.mode == :expedited

      {:ok, _} = Kura.activate_server(Repo.get!(Server, server.id), @target_tag)

      stub(Provisioner, :rollout_health, fn _server ->
        {:ok, healthy_health(%{memory_pressure_state: 2})}
      end)

      assert :ok = Rollouts.sync()

      reloaded = Repo.get!(Rollout, rollout.id)
      assert reloaded.status == :paused
      assert reloaded.pause_reason == "memory_pressure_critical"
    end

    test "an expedited rollout that never converges pauses at the deadline" do
      create_active_server()

      assert :ok = Rollouts.sync()
      rollout = Rollouts.active_rollout()
      assert rollout.mode == :expedited
      assert rollout.wave_started_at

      # Nothing converges (a deployment that never finishes). Without a clock
      # the rollout would sit :running forever and the promotion gate would
      # time out with nothing to point at.
      rollout = back_date(rollout, :wave_started_at, 61 * 60)
      assert :ok = Rollouts.sync()

      rollout = Repo.get!(Rollout, rollout.id)
      assert rollout.status == :paused
      assert rollout.pause_reason == "wave_deadline_exceeded"
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

    test "a soak-ineligible server's pre-existing sickness cannot pause the rollout" do
      %{account: canary_account, server: canary_server} = create_active_server()
      # A second, healthy account so the wave still carries gate evidence.
      create_active_server()

      stub(Tuist.Environment, :kura_canary_account_handles, fn -> [String.downcase(canary_account.name)] end)

      # Already at critical pressure when the wave schedules, which is one of
      # the conditions that makes a server soak-ineligible.
      stub(Provisioner, :rollout_health, fn server ->
        if server.id == canary_server.id do
          {:ok, healthy_health(%{memory_pressure_state: 2})}
        else
          {:ok, healthy_health()}
        end
      end)

      assert :ok = Rollouts.sync()
      rollout = Rollouts.active_rollout()
      refute rollout_server(rollout, canary_server).soak_eligible

      {:ok, _} = Kura.activate_server(Repo.get!(Server, canary_server.id), @target_tag)

      assert :ok = Rollouts.sync()

      # Sickness that pre-dates the wave is not attributed to the new image.
      # Re-raising it here paused the rollout with no verb able to clear it,
      # since resume only re-attempts servers that have not converged.
      rollout = Repo.get!(Rollout, rollout.id)
      assert rollout.status == :running
      assert is_nil(rollout.pause_reason)
    end

    test "a server reclaimed by the demand-driven lifecycle drops out of the wave" do
      %{account: canary_account, server: canary_server} = create_active_server()

      stub(Tuist.Environment, :kura_canary_account_handles, fn -> [String.downcase(canary_account.name)] end)

      assert :ok = Rollouts.sync()
      rollout = Rollouts.active_rollout()
      assert rollout_server(rollout, canary_server)

      # The lifecycle reclaims the idle instance mid-wave; the reconciler
      # cancels its deployment, so it can never converge on the target.
      {1, _} =
        Server
        |> where([s], s.id == ^canary_server.id)
        |> Repo.update_all(set: [status: :archived])

      assert :ok = Rollouts.sync()

      # The wave completes on the servers still in scope instead of holding
      # open until the deadline pauses the rollout.
      rollout = back_date(Repo.get!(Rollout, rollout.id), :wave_healthy_since, 16 * 60)
      assert :ok = Rollouts.sync()
      assert Repo.get!(Rollout, rollout.id).current_wave > 0
    end

    test "a cancelled attempt is re-minted once the server is back in scope" do
      %{account: canary_account, server: canary_server} = create_active_server()

      stub(Tuist.Environment, :kura_canary_account_handles, fn -> [String.downcase(canary_account.name)] end)

      assert :ok = Rollouts.sync()
      rollout = Rollouts.active_rollout()
      original = Repo.get!(Deployment, rollout_server(rollout, canary_server).deployment_id)

      # Entering drain cancels the deployment; demand then returns and the
      # server comes back on its old image with the dead id still attached.
      {:ok, _} = Kura.mark_cancelled(original, "server is drain_pending; skipping rollout")

      assert :ok = Rollouts.sync()

      rollout_server = rollout_server(rollout, canary_server)
      assert rollout_server.deployment_id != original.id
      assert Repo.get!(Deployment, rollout_server.deployment_id).status == :pending
    end

    test "a late joiner of the final wave is scoped before the rollout completes" do
      %{server: first_server} = create_active_server()

      assert :ok = Rollouts.sync()
      rollout = Rollouts.active_rollout()
      {:ok, _} = Kura.activate_server(Repo.get!(Server, first_server.id), @target_tag)

      # Let convergence be recorded first: it is marked after the completion
      # check, so without this tick the rollout could not complete anyway and
      # the test would pass whether or not the unscoped check exists.
      assert :ok = Rollouts.sync()
      assert rollout_server(rollout, first_server).converged_at

      # A server whose account has no wave assignment yet appears while the
      # rollout sits past its last wave, one tick from completing.
      %{server: late_server} = create_active_server()

      {1, _} =
        Rollout
        |> where([r], r.id == ^rollout.id)
        |> Repo.update_all(set: [current_wave: 4])

      assert :ok = Rollouts.sync()

      # Everything scoped has converged, so without the unscoped check the
      # rollout would complete here and leave the late server behind.
      rollout = Repo.get!(Rollout, rollout.id)
      assert rollout.status == :running
      assert rollout_server(rollout, late_server)
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

  describe "the health gate arithmetic" do
    setup do
      stub(Tuist.Environment, :kura_rollout_pacing, fn -> "progressive" end)
      :ok
    end

    # Drives one converged, soak-eligible server to the point where the gate
    # is the only thing deciding, then reports whether the wave advanced.
    # Each call mints its own rollout (a fresh target tag supersedes the
    # previous one) so several verdicts can be taken in a single test.
    defp gate_verdict(baseline_health, post_health) do
      target = "0.6.#{System.unique_integer([:positive])}"
      stub(Tuist.Environment, :kura_runtime_image_tag, fn -> target end)

      %{account: account, server: server} = create_active_server()
      stub(Tuist.Environment, :kura_canary_account_handles, fn -> [String.downcase(account.name)] end)
      stub(Provisioner, :rollout_health, fn _server -> {:ok, baseline_health} end)

      assert :ok = Rollouts.sync()
      rollout = Rollouts.active_rollout()
      assert rollout.image_tag == target
      assert rollout_server(rollout, server).soak_eligible

      {:ok, _} = Kura.activate_server(Repo.get!(Server, server.id), target)
      stub(Provisioner, :rollout_health, fn _server -> {:ok, post_health} end)

      assert :ok = Rollouts.sync()
      rollout = back_date(Repo.get!(Rollout, rollout.id), :wave_healthy_since, 16 * 60)
      assert :ok = Rollouts.sync()

      rollout = Repo.get!(Rollout, rollout.id)
      if rollout.current_wave > 0, do: :passed, else: :held
    end

    test "outbox within the tolerance band passes and beyond it holds" do
      # baseline 100 -> band is 100 + max(ceil(100/10), 50) = 150.
      assert gate_verdict(healthy_health(%{outbox_messages: 100}), healthy_health(%{outbox_messages: 150})) ==
               :passed

      assert gate_verdict(healthy_health(%{outbox_messages: 100}), healthy_health(%{outbox_messages: 151})) ==
               :held
    end

    test "failure counters tolerate the rollout's own reconnect churn" do
      # A rollout restarts every pod, so a handful of new peer errors is
      # expected; sustained growth past the band is not.
      assert gate_verdict(
               healthy_health(%{peer_connection_failures: 0}),
               healthy_health(%{peer_connection_failures: 25})
             ) == :passed

      assert gate_verdict(
               healthy_health(%{peer_connection_failures: 0}),
               healthy_health(%{peer_connection_failures: 26})
             ) == :held
    end

    test "a counter that went backwards after a restart is not a regression" do
      assert gate_verdict(
               healthy_health(%{fd_timeout_count: 90}),
               healthy_health(%{fd_timeout_count: 3})
             ) == :passed
    end

    test "a counter the aggregate never reported is not compared" do
      # A runtime predating the counter reports nothing, so the baseline is
      # unknown; the first reading from a newer runtime must not read as a
      # regression from a baseline that was never measured.
      assert gate_verdict(
               healthy_health(%{peer_connection_failures: nil}),
               healthy_health(%{peer_connection_failures: 40})
             ) == :passed
    end

    test "each absolute condition holds the wave" do
      for {label, overrides} <- [
            {:not_ready, %{ready: false}},
            {:not_serving, %{serving: false}},
            {:ring_skew, %{ring_consistent: false}},
            {:backfill_degraded, %{backfill_degraded: true}},
            {:backfill_budget, %{backfill_budget_exhausted_peers: 2}},
            {:pods_unsampled, %{sampled_pods: 0, expected_pods: 1}},
            {:sample_stale, %{sampled_at: DateTime.add(DateTime.utc_now(), -10 * 60, :second)}}
          ] do
        assert gate_verdict(healthy_health(), healthy_health(overrides)) == :held,
               "expected #{label} to hold the wave"
      end
    end

    test "backfill merely in flight does not hold the wave" do
      # Expected work after a rollout restarts a pod, and indistinguishable
      # from a stalled node, so it is not a signal on its own.
      assert gate_verdict(healthy_health(), healthy_health(%{backfilling_peers: 3})) == :passed
    end
  end

  describe "operator verbs" do
    setup do
      stub(Tuist.Environment, :kura_rollout_pacing, fn -> "progressive" end)
      :ok
    end

    test "a pre-existing ring skew makes the server soak-ineligible instead of gating its fix" do
      %{account: canary_account, server: canary_server} = create_active_server()

      stub(Tuist.Environment, :kura_canary_account_handles, fn -> [String.downcase(canary_account.name)] end)

      stub(Provisioner, :rollout_health, fn _server ->
        {:ok, healthy_health(%{ring_consistent: false})}
      end)

      assert :ok = Rollouts.sync()
      rollout = Rollouts.active_rollout()

      rollout_server = rollout_server(rollout, canary_server)
      refute rollout_server.soak_eligible
      assert rollout_server.deployment_id
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

    test "a superseding rollout keeps fresh servers on the account's actual tag, not the oldest baseline" do
      %{account: upgraded_account, server: upgraded_server} = create_active_server()
      %{account: pending_account} = create_active_server()

      stub(Tuist.Environment, :kura_canary_account_handles, fn -> [String.downcase(upgraded_account.name)] end)
      stub(Tuist.FeatureFlags, :kura_rollout_orchestration_enabled?, fn -> true end)

      # Rollout B (baseline A): the canary account converges and its wave
      # completes; the other account's wave never runs.
      assert :ok = Rollouts.sync()
      rollout_b = Rollouts.active_rollout()

      {1, _} =
        Rollout
        |> where([r], r.id == ^rollout_b.id)
        |> Repo.update_all(set: [baseline_image_tag: @baseline_tag])

      {:ok, _} = Kura.activate_server(Repo.get!(Server, upgraded_server.id), @target_tag)
      assert :ok = Rollouts.sync()
      back_date(Repo.get!(Rollout, rollout_b.id), :wave_healthy_since, 16 * 60)
      assert :ok = Rollouts.sync()
      assert Repo.get!(Rollout, rollout_b.id).current_wave == 1

      # Rollout C supersedes B; its global baseline chains back to A.
      stub(Tuist.Environment, :kura_runtime_image_tag, fn -> "0.7.0" end)
      assert :ok = Rollouts.sync()

      rollout_c = Rollouts.active_rollout()
      assert rollout_c.image_tag == "0.7.0"
      assert rollout_c.baseline_image_tag == @baseline_tag

      # The upgraded account's mesh runs B: a fresh server must get B, not
      # regress to A. The never-upgraded account stays on A.
      assert Rollouts.provisioning_image_tag(upgraded_account.id, "0.7.0") == @target_tag
      assert Rollouts.provisioning_image_tag(pending_account.id, "0.7.0") == @baseline_tag
    end

    test "a paused first rollout pins an account with no server to the fleet baseline" do
      # The first rollout has no previous rollout to inherit a baseline
      # from, and an account with no server has no mesh tag to match, so
      # both of the earlier fallbacks are empty. Without a fleet-derived
      # baseline this handed out the paused, suspect target.
      %{server: fleet_server} = create_active_server()
      assert Repo.get!(Server, fleet_server.id).current_image_tag == @baseline_tag

      stub(Tuist.FeatureFlags, :kura_rollout_orchestration_enabled?, fn -> true end)

      assert :ok = Rollouts.sync()
      rollout = Rollouts.active_rollout()
      {:ok, _} = Rollouts.pause(rollout, "op@tuist.dev", "target looks suspect")

      user = AccountsFixtures.user_fixture()
      fresh_account = Accounts.get_account_from_user(user)

      assert Rollouts.provisioning_image_tag(fresh_account.id, @target_tag) == @baseline_tag
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
