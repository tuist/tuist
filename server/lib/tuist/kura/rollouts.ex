defmodule Tuist.Kura.Rollouts do
  @moduledoc """
  Health-gated progressive rollout of Kura runtime image versions
  ([spec #79](https://hive.tuist.dev/specs/79)).

  A rollout is durable control-plane state advanced one reconciler tick at
  a time (`sync/0`). When the configured runtime tag changes, the active
  rollout is superseded and a new one minted with deterministic
  account-grouped waves: wave 0 is the Tuist-owned canary accounts, waves
  1..3 split the remaining accounts by recent Kura usage ascending. Each
  wave must converge on the target image and then hold the health gate
  continuously for a soak period before the next wave schedules.

  The gate measures regression, not absolute health: per-server counters
  (outbox depth, file-descriptor wait timeouts, peer-connection failures)
  are compared against a baseline captured just before the server's wave
  scheduled, on top of the absolute conditions the standalone chart gate
  already proved (ready, serving, generation-consistent, no bootstrap in
  flight, no critical memory pressure, fresh sample). The health authority
  is the `KuraInstance` status aggregate the Go controller publishes from
  the per-pod `/status/rollout` reports; it never crosses the public
  gateway.

  Scheduling is at-most-once per rollout *attempt*, deliberately replacing
  the per-server-per-tag-lifetime invariant of the interim scheduler:
  resume means re-attempt (fresh deployments for every non-converged
  server, including previously failed ones), not re-evaluate.

  Pacing applies to production only; the other environments mint their
  rollouts in `:expedited` mode, which is the all-at-once fan-out. The
  deploy pipeline gates production promotion on the canary environment's
  rollout record completing.
  """

  import Ecto.Query

  alias Phoenix.PubSub
  alias Tuist.Environment
  alias Tuist.Kura
  alias Tuist.Kura.Deployment
  alias Tuist.Kura.Provisioner
  alias Tuist.Kura.Rollout
  alias Tuist.Kura.RolloutEvent
  alias Tuist.Kura.Rollouts.Notifier
  alias Tuist.Kura.RolloutServer
  alias Tuist.Kura.RolloutWaveAssignment
  alias Tuist.Kura.Server
  alias Tuist.Kura.Usage
  alias Tuist.Repo

  require Logger

  @pubsub Tuist.PubSub
  @topic "kura:rollouts"

  # Mirrors Tuist.Kura's @version_rollout_statuses: a version rollout must
  # reach degraded servers, not only healthy ones; only terminal servers
  # are out of scope.
  @rollout_server_statuses [:provisioning, :replicating, :active, :failed]
  @terminal_server_statuses [:destroying, :destroyed]
  @open_deployment_statuses [:pending, :running]

  # Wave sizing over the non-canary accounts, ordered by recent usage
  # ascending. Proposed by the spec; revisit after the first monitored
  # production rollout.
  @wave_one_fraction 0.05
  @wave_two_fraction 0.25
  @last_wave 3

  # Soak-reset-then-deadline gate pacing, mirroring the standalone chart
  # gate: transient blips reset the continuous-health clock instead of
  # pausing the world; a wave that cannot complete within the deadline
  # pauses the rollout.
  @canary_soak_seconds 15 * 60
  @wave_soak_seconds 5 * 60
  @wave_deadline_seconds 60 * 60

  # A health sample older than this reads as unhealthy: the controller
  # publishes the aggregate every ~30s, so three missed cycles means the
  # report is a frozen snapshot, not evidence.
  @health_sample_max_age_seconds 180

  # Outbox depth may sit 10% above its pre-upgrade baseline (rounded up,
  # matching gate.sh) with a small absolute floor so near-zero baselines
  # don't flap the gate on a handful of in-flight messages.
  @outbox_regression_floor 50

  @usage_window_days 7

  ## Tick entrypoint

  @doc """
  Advances rollout state one tick: ensures a rollout exists for the
  configured runtime tag (superseding the active one on a tag change,
  never on a same-tag redeploy) and advances the non-terminal rollout.
  Called from `Tuist.Kura.Reconciler` when rollout orchestration is
  enabled.
  """
  def sync do
    case configured_image_tag() do
      nil ->
        :ok

      tag ->
        tag
        |> ensure_rollout()
        |> advance()
    end
  end

  defp configured_image_tag do
    case Environment.kura_runtime_image_tag() do
      tag when is_binary(tag) ->
        with "" <- String.trim(tag), do: nil

      _ ->
        nil
    end
  end

  ## Lookups

  def get_rollout(id), do: Repo.get(Rollout, id)

  @doc "The single non-terminal (running or paused) rollout, or nil."
  def active_rollout do
    Rollout
    |> where([r], r.status in [:running, :paused])
    |> Repo.one()
  end

  def latest_rollout do
    Rollout
    |> order_by([r], desc: r.inserted_at, desc: r.id)
    |> limit(1)
    |> Repo.one()
  end

  def latest_rollout_for_tag(image_tag) when is_binary(image_tag) do
    Rollout
    |> where([r], r.image_tag == ^image_tag)
    |> order_by([r], desc: r.inserted_at, desc: r.id)
    |> limit(1)
    |> Repo.one()
  end

  def list_rollouts(limit \\ 20) do
    Rollout
    |> order_by([r], desc: r.inserted_at, desc: r.id)
    |> limit(^limit)
    |> Repo.all()
  end

  def list_events(%Rollout{id: id}, limit \\ 50) do
    RolloutEvent
    |> where([e], e.kura_rollout_id == ^id)
    |> order_by([e], desc: e.inserted_at, desc: e.id)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Per-wave progress for the ops view and the rollout metrics: account and
  server counts, converged and soak-eligible servers, per wave.
  """
  def wave_summary(%Rollout{id: id}) do
    accounts_by_wave =
      RolloutWaveAssignment
      |> where([w], w.kura_rollout_id == ^id)
      |> group_by([w], w.wave)
      |> select([w], {w.wave, count(w.id)})
      |> Repo.all()
      |> Map.new()

    server_rows =
      RolloutServer
      |> where([rs], rs.kura_rollout_id == ^id)
      |> group_by([rs], rs.wave)
      |> select([rs], %{
        wave: rs.wave,
        servers: count(rs.id),
        converged: count(fragment("CASE WHEN ? IS NOT NULL THEN 1 END", rs.converged_at)),
        soak_eligible: count(fragment("CASE WHEN ? THEN 1 END", rs.soak_eligible))
      })
      |> Repo.all()
      |> Map.new(&{&1.wave, &1})

    accounts_by_wave
    |> Map.keys()
    |> Enum.concat(Map.keys(server_rows))
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.map(fn wave ->
      servers = Map.get(server_rows, wave, %{servers: 0, converged: 0, soak_eligible: 0})

      %{
        wave: wave,
        accounts: Map.get(accounts_by_wave, wave, 0),
        servers: servers.servers,
        converged: servers.converged,
        soak_eligible: servers.soak_eligible
      }
    end)
  end

  @doc "Whether a rollout of this tag has ever completed in this environment."
  def previously_completed?(image_tag) when is_binary(image_tag) do
    Rollout
    |> where([r], r.image_tag == ^image_tag and r.status == :completed)
    |> Repo.exists?()
  end

  @doc """
  Servers per observed image tag across the non-destroyed fleet — the
  version-distribution series behind the rollout dashboard's convergence
  curve.
  """
  def fleet_version_distribution do
    Server
    |> where([s], s.status != :destroyed)
    |> group_by([s], s.observed_image_tag)
    |> select([s], {s.observed_image_tag, count(s.id)})
    |> Repo.all()
    |> Map.new(fn {tag, count} -> {tag || "unknown", count} end)
  end

  ## Mid-rollout server provisioning

  @doc """
  The image tag a server created right now for `account_id` should
  provision on. Servers created mid-rollout inherit their account's wave
  state instead of jumping to the configured tag: until the account's
  wave has completed they provision on the rollout's baseline tag, after
  it on the target. A paused rollout — whatever its mode, including the
  expedited fan-outs the canary/staging environments run — pins every
  fresh server to the baseline: the pause marked the target as suspect,
  and new or retried runner-cache servers take traffic the moment they
  exist.
  """
  def provisioning_image_tag(account_id, default_tag) do
    if Tuist.FeatureFlags.kura_rollout_orchestration_enabled?() do
      case active_rollout() do
        nil -> default_tag
        %Rollout{status: :paused} = rollout -> rollout.baseline_image_tag || default_tag
        %Rollout{mode: :progressive} = rollout -> inherited_image_tag(rollout, account_id, default_tag)
        %Rollout{mode: :expedited} -> default_tag
      end
    else
      default_tag
    end
  end

  defp inherited_image_tag(rollout, account_id, default_tag) do
    wave =
      RolloutWaveAssignment
      |> where([w], w.kura_rollout_id == ^rollout.id and w.account_id == ^account_id)
      |> select([w], w.wave)
      |> Repo.one()

    if not is_nil(wave) and wave < rollout.current_wave do
      rollout.image_tag
    else
      rollout.baseline_image_tag || default_tag
    end
  end

  ## Rollout minting and supersede

  defp ensure_rollout(tag) do
    case active_rollout() do
      %Rollout{image_tag: ^tag} = rollout ->
        # A server-only redeploy carries the same tag: an active or paused
        # rollout is left untouched, so a paused rollout cannot be
        # accidentally reset by the next unrelated merge.
        rollout

      %Rollout{} = active ->
        supersede(active, tag)
        create_rollout(tag, active)

      nil ->
        case latest_rollout() do
          %Rollout{image_tag: ^tag} = rollout -> rollout
          previous -> create_rollout(tag, previous)
        end
    end
  end

  defp supersede(%Rollout{status: status} = rollout, tag) when status in [:running, :paused] do
    rollout
    |> Rollout.update_changeset(%{status: :superseded})
    |> Repo.update!()

    cancel_open_rollout_deployments(rollout, "superseded by rollout of #{tag}")

    record_event(rollout, "superseded", "system", nil, %{superseded_by: tag})
    Notifier.notify(:superseded, rollout, %{superseded_by: tag})
    :ok
  end

  defp supersede(%Rollout{}, _tag), do: :ok

  defp create_rollout(tag, previous) do
    mode = initial_mode(tag)
    baseline = baseline_image_tag(previous)

    metadata = %{
      mode: Atom.to_string(mode),
      source_tag: baseline,
      target_tag: tag,
      previously_completed: previously_completed?(tag)
    }

    # Wave assignments are computed before the transaction (they read
    # ClickHouse usage) and committed atomically with the rollout row:
    # a rollout must never become visible with partial assignments, or
    # the missing-account backstop would flatten the canary/5%/25%
    # ordering into the last wave.
    assignments = compute_wave_assignments(previous)

    {:ok, rollout} =
      Repo.transaction(fn ->
        {:ok, rollout} =
          %{image_tag: tag, baseline_image_tag: baseline, mode: mode}
          |> Rollout.create_changeset()
          |> Repo.insert()

        insert_wave_assignments(rollout, assignments)
        record_event(rollout, "created", "system", nil, metadata)

        if mode == :expedited and expedited_by_deploy_input?(tag) do
          record_event(rollout, "expedited", "deploy-input", "expedited at creation via deployment input", metadata)
        end

        rollout
      end)

    Notifier.notify(:started, rollout, metadata)
    rollout
  end

  # Only production paces by default. The canary and staging environments
  # exist to expose a new version to real usage as early as possible, so
  # their rollouts fan out immediately; their rollout record still gates
  # the pipeline's production promotion. An explicit deploy-input expedite
  # (rollback to a proven tag) also starts expedited — for exactly the
  # requested tag, never inferred. TUIST_KURA_ROLLOUT_PACING overrides
  # the environment default for the staging progressive-mode drills.
  defp initial_mode(tag) do
    cond do
      expedited_by_deploy_input?(tag) -> :expedited
      progressive_environment?() -> :progressive
      true -> :expedited
    end
  end

  defp progressive_environment? do
    case Environment.kura_rollout_pacing() do
      "progressive" -> true
      "expedited" -> false
      nil -> Environment.env() == :prod
    end
  end

  defp expedited_by_deploy_input?(tag), do: Environment.kura_rollout_expedite_tag() == tag

  # The tag the fleet was on before this rollout: the previous rollout's
  # target if it completed, else the last stable tag it was itself rolling
  # away from. Nil only before the first rollout ever, where new servers
  # simply provision on the configured tag.
  defp baseline_image_tag(nil), do: nil
  defp baseline_image_tag(%Rollout{status: :completed, image_tag: tag}), do: tag
  defp baseline_image_tag(%Rollout{baseline_image_tag: tag}), do: tag

  # Deterministic account-grouped wave assignment, frozen at creation.
  # Wave 0: Tuist-owned accounts only. Waves 1..3: remaining accounts by
  # recent usage ascending (lower-traffic accounts absorb earlier
  # exposure), tie-broken by account id. A superseding rollout orders
  # accounts still on the oldest image first after the canary, to collapse
  # version skew quickly.
  defp compute_wave_assignments(previous) do
    accounts = accounts_with_rollout_servers()
    canary_handles = MapSet.new(Environment.kura_canary_account_handles())

    {canary, rest} =
      Enum.split_with(accounts, fn {_id, name} ->
        MapSet.member?(canary_handles, String.downcase(name))
      end)

    usage = Usage.recent_request_counts_by_account(Enum.map(rest, &elem(&1, 0)), @usage_window_days)
    on_oldest = accounts_on_oldest_image(previous)

    rest =
      Enum.sort_by(rest, fn {id, _name} ->
        {if(MapSet.member?(on_oldest, id), do: 0, else: 1), Map.get(usage, id, 0), id}
      end)

    wave_one_count = fraction_count(length(rest), @wave_one_fraction)
    wave_two_count = fraction_count(length(rest), @wave_two_fraction)

    {wave_one, rest} = Enum.split(rest, wave_one_count)
    {wave_two, wave_three} = Enum.split(rest, wave_two_count)

    Enum.map(canary, &{elem(&1, 0), 0}) ++
      Enum.map(wave_one, &{elem(&1, 0), 1}) ++
      Enum.map(wave_two, &{elem(&1, 0), 2}) ++ Enum.map(wave_three, &{elem(&1, 0), @last_wave})
  end

  defp insert_wave_assignments(rollout, assignments) do
    Enum.each(assignments, fn {account_id, wave} ->
      {:ok, _} =
        %{kura_rollout_id: rollout.id, account_id: account_id, wave: wave}
        |> RolloutWaveAssignment.create_changeset()
        |> Repo.insert()
    end)
  end

  defp fraction_count(0, _fraction), do: 0
  defp fraction_count(count, fraction), do: max(ceil(count * fraction), 1)

  defp accounts_with_rollout_servers do
    Server
    |> where([s], s.status in ^@rollout_server_statuses and s.move_phase == :none)
    |> join(:inner, [s], a in assoc(s, :account))
    |> distinct([_s, a], a.id)
    |> select([_s, a], {a.id, a.name})
    |> Repo.all()
  end

  defp accounts_on_oldest_image(%Rollout{status: status, baseline_image_tag: oldest})
       when status in [:running, :paused] and is_binary(oldest) do
    Server
    |> where([s], s.status in ^@rollout_server_statuses and s.move_phase == :none)
    |> where([s], s.current_image_tag == ^oldest)
    |> select([s], s.account_id)
    |> Repo.all()
    |> MapSet.new()
  end

  defp accounts_on_oldest_image(_previous), do: MapSet.new()

  ## Advancing

  defp advance(%Rollout{status: status}) when status not in [:running], do: :ok

  defp advance(%Rollout{} = rollout) do
    with_locked_rollout(rollout.id, fn
      %Rollout{status: :running, mode: :expedited} = rollout -> advance_expedited(rollout)
      %Rollout{status: :running, mode: :progressive} = rollout -> advance_progressive(rollout)
      _ -> :ok
    end)

    :ok
  end

  defp advance_expedited(rollout) do
    assign_missing_accounts(rollout)
    scope_servers(rollout, max_wave(rollout))
    mint_missing_deployments(rollout)
    mark_convergences(rollout)

    cond do
      failure = hard_failure(rollout) ->
        pause_rollout(rollout, failure)

      all_converged?(rollout) ->
        complete_rollout(rollout)

      true ->
        :ok
    end
  end

  defp advance_progressive(rollout) do
    assign_missing_accounts(rollout)

    case open_current_wave(rollout) do
      {:completed, _rollout} ->
        :ok

      {:open, rollout} ->
        scope_servers(rollout, rollout.current_wave)
        mint_missing_deployments(rollout)
        mark_convergences(rollout)

        if failure = hard_failure(rollout) do
          pause_rollout(rollout, failure)
        else
          evaluate_wave(rollout)
        end
    end
  end

  # Advances past empty waves (an environment with no Tuist-owned servers
  # has an empty canary, for example) and stamps wave_started_at when the
  # current wave first opens. Completes the rollout when every wave is
  # exhausted and everything scoped has converged.
  defp open_current_wave(rollout) do
    cond do
      rollout.current_wave > max_wave(rollout) ->
        if all_converged?(rollout) and is_nil(gate_failure(rollout)) do
          {:completed, complete_rollout(rollout)}
        else
          # Late joiners of already-completed waves still converge under
          # the fleet-wide gate before the rollout completes.
          {:open, stamp_wave_started(rollout)}
        end

      wave_empty?(rollout, rollout.current_wave) ->
        record_event(rollout, "wave_completed", "system", nil, %{wave: rollout.current_wave, empty: true})

        rollout
        |> Rollout.update_changeset(%{
          current_wave: rollout.current_wave + 1,
          wave_started_at: nil,
          wave_healthy_since: nil
        })
        |> Repo.update!()
        |> open_current_wave()

      true ->
        {:open, stamp_wave_started(rollout)}
    end
  end

  defp stamp_wave_started(%Rollout{wave_started_at: nil} = rollout) do
    rollout |> Rollout.update_changeset(%{wave_started_at: now()}) |> Repo.update!()
  end

  defp stamp_wave_started(rollout), do: rollout

  defp max_wave(rollout) do
    RolloutWaveAssignment
    |> where([w], w.kura_rollout_id == ^rollout.id)
    |> select([w], max(w.wave))
    |> Repo.one()
    |> Kernel.||(-1)
  end

  defp wave_empty?(rollout, wave) do
    scoped? =
      RolloutServer
      |> where([rs], rs.kura_rollout_id == ^rollout.id and rs.wave == ^wave)
      |> Repo.exists?()

    schedulable? =
      rollout
      |> schedulable_servers_query(wave)
      |> Repo.exists?()

    not scoped? and not schedulable?
  end

  # Accounts whose servers appeared after wave assignment (created
  # mid-rollout) join the last wave rather than bypassing the rollout.
  defp assign_missing_accounts(rollout) do
    assigned =
      RolloutWaveAssignment
      |> where([w], w.kura_rollout_id == ^rollout.id)
      |> select([w], w.account_id)

    missing =
      Server
      |> where([s], s.status in ^@rollout_server_statuses and s.move_phase == :none)
      |> where([s], s.account_id not in subquery(assigned))
      |> distinct([s], s.account_id)
      |> select([s], s.account_id)
      |> Repo.all()

    Enum.each(missing, fn account_id ->
      {:ok, _} =
        %{kura_rollout_id: rollout.id, account_id: account_id, wave: max(max_wave(rollout), @last_wave)}
        |> RolloutWaveAssignment.create_changeset()
        |> Repo.insert()
    end)
  end

  # Servers of accounts assigned to waves <= max_open_wave that are not
  # yet in rollout scope. Runs every tick so servers created mid-rollout
  # (or healed into eligibility) join their account's wave late rather
  # than escaping the rollout.
  defp schedulable_servers_query(rollout, max_open_wave) do
    scoped =
      RolloutServer
      |> where([rs], rs.kura_rollout_id == ^rollout.id)
      |> select([rs], rs.kura_server_id)

    Server
    |> where([s], s.status in ^@rollout_server_statuses and s.move_phase == :none)
    |> where([s], s.id not in subquery(scoped))
    |> join(:inner, [s], w in RolloutWaveAssignment,
      on: w.account_id == s.account_id and w.kura_rollout_id == ^rollout.id and w.wave <= ^max_open_wave
    )
    |> select([s, w], {s, w.wave})
  end

  defp scope_servers(rollout, max_open_wave) do
    rollout
    |> schedulable_servers_query(max_open_wave)
    |> Repo.all()
    |> Enum.each(fn {server, wave} -> scope_server(rollout, server, wave) end)
  end

  # Brings one server into rollout scope: captures its pre-upgrade health
  # baseline (deciding soak eligibility), and mints — or adopts — the
  # deployment that will carry it to the target image. A server already
  # observed on the target converges immediately with no deployment.
  defp scope_server(rollout, %Server{} = server, wave) do
    {baseline, soak_eligible} = capture_baseline(server)

    attrs = %{
      kura_rollout_id: rollout.id,
      kura_server_id: server.id,
      wave: wave,
      soak_eligible: soak_eligible,
      baseline_outbox_messages: baseline[:outbox_messages],
      baseline_fd_timeout_count: baseline[:fd_timeout_count],
      baseline_peer_connection_failures: baseline[:peer_connection_failures],
      baseline_captured_at: now()
    }

    attrs =
      if server.observed_image_tag == rollout.image_tag do
        Map.put(attrs, :converged_at, now())
      else
        Map.put(attrs, :deployment_id, mint_deployment(rollout, server))
      end

    {:ok, _} = attrs |> RolloutServer.create_changeset() |> Repo.insert()
    :ok
  end

  # Adopts a same-tag open deployment (a server created mid-rollout after
  # its wave completed provisions directly on the target) or mints a new
  # one. A server can hold only one open deployment at a time; when a
  # different-tag deployment is still open (initial install, warm-handoff
  # move), minting yields nil and `mint_missing_deployments/1` retries on
  # a later tick once that deployment closes.
  defp mint_deployment(rollout, server) do
    case adoptable_open_deployment(server, rollout.image_tag) do
      %Deployment{id: deployment_id} ->
        deployment_id

      nil ->
        case Kura.create_deployment(server, rollout.image_tag, rollout_id: rollout.id) do
          {:ok, deployment} ->
            deployment.id

          {:error, :deployment_in_progress} ->
            Logger.info("[Kura.Rollouts] server #{server.id} has an open deployment; deferring the rollout deployment")

            nil

          {:error, reason} ->
            Logger.warning("[Kura.Rollouts] could not mint deployment for server #{server.id}: #{inspect(reason)}")

            nil
        end
    end
  end

  # Scoped servers whose deployment could not be minted yet (an initial
  # install or move deployment was still open) get their rollout
  # deployment as soon as the server frees up.
  defp mint_missing_deployments(rollout) do
    RolloutServer
    |> join(:inner, [rs], s in assoc(rs, :kura_server))
    |> where([rs], rs.kura_rollout_id == ^rollout.id and is_nil(rs.deployment_id) and is_nil(rs.converged_at))
    |> where([_rs, s], s.status not in ^@terminal_server_statuses and s.move_phase == :none)
    |> preload([rs, s], kura_server: s)
    |> Repo.all()
    |> Enum.each(fn rollout_server ->
      case mint_deployment(rollout, rollout_server.kura_server) do
        nil ->
          :ok

        deployment_id ->
          {:ok, _} =
            rollout_server
            |> RolloutServer.update_changeset(%{deployment_id: deployment_id})
            |> Repo.update()
      end
    end)
  end

  # A server created mid-rollout after its wave completed provisions
  # directly on the target: its initial install deployment already carries
  # the tag, so the rollout adopts it instead of double-deploying.
  defp adoptable_open_deployment(server, image_tag) do
    Deployment
    |> where([d], d.kura_server_id == ^server.id and d.image_tag == ^image_tag)
    |> where([d], d.status in ^@open_deployment_statuses)
    |> order_by([d], desc: d.inserted_at, desc: d.id)
    |> limit(1)
    |> Repo.one()
  end

  defp capture_baseline(server) do
    case Provisioner.rollout_health(server) do
      {:ok, health} when is_map(health) ->
        baseline = %{
          outbox_messages: health.outbox_messages,
          fd_timeout_count: health.fd_timeout_count,
          peer_connection_failures: health.peer_connection_failures
        }

        {baseline, baseline_healthy?(health)}

      _ ->
        # No aggregate to compare against: convergence is still required,
        # but there is no honest baseline for the comparative soak, so the
        # server is ungated. This is also what keeps the gate from
        # standing between a broken fleet and its fix.
        {%{}, false}
    end
  end

  defp baseline_healthy?(health) do
    health.ready and health.serving and health.sampled_pods >= health.expected_pods and
      health.memory_pressure_state < 2 and fresh_sample?(health)
  end

  defp fresh_sample?(%{sampled_at: %DateTime{} = sampled_at}) do
    DateTime.diff(now(), sampled_at, :second) <= @health_sample_max_age_seconds
  end

  defp fresh_sample?(_health), do: false

  # Every scheduled deployment must observe the target image before its
  # wave can complete; observation is recorded by the reconciler's
  # projection (`observed_image_tag`). Servers destroyed mid-rollout drop
  # out of both convergence and gate scope.
  defp mark_convergences(rollout) do
    timestamp = now()

    converged_ids =
      RolloutServer
      |> join(:inner, [rs], s in assoc(rs, :kura_server))
      |> where([rs], rs.kura_rollout_id == ^rollout.id and is_nil(rs.converged_at))
      |> where([_rs, s], s.observed_image_tag == ^rollout.image_tag)
      |> where([_rs, s], s.status not in ^@terminal_server_statuses)
      |> select([rs], rs.id)
      |> Repo.all()

    if converged_ids != [] do
      RolloutServer
      |> where([rs], rs.id in ^converged_ids)
      |> Repo.update_all(set: [converged_at: timestamp, updated_at: timestamp])
    end

    :ok
  end

  defp all_converged?(rollout) do
    RolloutServer
    |> join(:inner, [rs], s in assoc(rs, :kura_server))
    |> where([rs], rs.kura_rollout_id == ^rollout.id and is_nil(rs.converged_at))
    |> where([_rs, s], s.status not in ^@terminal_server_statuses)
    |> Repo.exists?()
    |> Kernel.not()
  end

  # Hard signals pause immediately, whatever the soak clock says: a
  # deployment reaching terminal failure, or a server regressing to
  # failed after it converged on the new image. (Critical memory pressure
  # is the third hard signal; it surfaces through the gate evaluation,
  # which reads the health aggregate anyway.)
  defp hard_failure(rollout) do
    failed_deployment(rollout) || regressed_after_convergence(rollout)
  end

  defp failed_deployment(rollout) do
    row =
      RolloutServer
      |> join(:inner, [rs], d in assoc(rs, :deployment))
      |> join(:inner, [rs], s in assoc(rs, :kura_server))
      |> where([rs], rs.kura_rollout_id == ^rollout.id and is_nil(rs.converged_at))
      |> where([_rs, d], d.status == :failed)
      |> where([_rs, _d, s], s.status not in ^@terminal_server_statuses)
      |> select([rs, d, s], %{server_id: s.id, region: s.region, deployment_id: d.id, error: d.error_message})
      |> limit(1)
      |> Repo.one()

    if row do
      {:deployment_failed,
       %{server_id: row.server_id, region: row.region, deployment_id: row.deployment_id, error: row.error}}
    end
  end

  defp regressed_after_convergence(rollout) do
    row =
      RolloutServer
      |> join(:inner, [rs], s in assoc(rs, :kura_server))
      |> where([rs], rs.kura_rollout_id == ^rollout.id and not is_nil(rs.converged_at))
      |> where([_rs, s], s.status == :failed)
      |> select([rs, s], %{server_id: s.id, region: s.region})
      |> limit(1)
      |> Repo.one()

    if row do
      {:server_regressed_to_failed, %{server_id: row.server_id, region: row.region}}
    end
  end

  # Soak, then pause rather than proceed: the wave completes when every
  # scoped deployment has converged and all soak-eligible servers have
  # passed the gate continuously for the soak period. Any failing tick
  # resets the clock; exceeding the wave deadline pauses the rollout.
  defp evaluate_wave(rollout) do
    gate = gate_failure(rollout)

    case gate do
      {:critical, details} ->
        pause_rollout(rollout, {details.signal, details})

      nil ->
        if all_converged?(rollout) do
          healthy_since = rollout.wave_healthy_since || now()
          rollout = persist_healthy_since(rollout, healthy_since)

          if DateTime.diff(now(), healthy_since, :second) >= soak_seconds(rollout.current_wave) do
            complete_wave(rollout)
          else
            :ok
          end
        else
          reset_health_clock_and_check_deadline(rollout)
        end

      {:unhealthy, _failure} ->
        reset_health_clock_and_check_deadline(rollout)
    end
  end

  defp persist_healthy_since(%Rollout{wave_healthy_since: nil} = rollout, healthy_since) do
    rollout |> Rollout.update_changeset(%{wave_healthy_since: healthy_since}) |> Repo.update!()
  end

  defp persist_healthy_since(rollout, _healthy_since), do: rollout

  defp reset_health_clock_and_check_deadline(rollout) do
    rollout =
      if rollout.wave_healthy_since do
        rollout |> Rollout.update_changeset(%{wave_healthy_since: nil}) |> Repo.update!()
      else
        rollout
      end

    deadline_exceeded? =
      rollout.wave_started_at &&
        DateTime.diff(now(), rollout.wave_started_at, :second) >= @wave_deadline_seconds

    if deadline_exceeded? do
      pause_rollout(rollout, {:wave_deadline_exceeded, %{wave: rollout.current_wave}})
    else
      :ok
    end
  end

  defp soak_seconds(0), do: @canary_soak_seconds
  defp soak_seconds(_wave), do: @wave_soak_seconds

  # The gate is evaluated over every server updated so far in the
  # rollout — not only the current wave — so a slow-burn regression
  # surfacing in the canary still stops wave 2 from scheduling.
  # Soak-ineligible servers (unhealthy at wave-schedule time) skip only
  # the comparative and absolute soak conditions; the critical safety
  # signal (memory pressure) still applies to them. Returns nil when all
  # pass, `{:unhealthy, details}` for a soak-clock reset, or
  # `{:critical, details}` for an immediate pause.
  defp gate_failure(rollout) do
    failures =
      RolloutServer
      |> join(:inner, [rs], s in assoc(rs, :kura_server))
      |> where([rs], rs.kura_rollout_id == ^rollout.id and not is_nil(rs.converged_at))
      |> where([_rs, s], s.status not in ^@terminal_server_statuses)
      |> preload([rs, s], kura_server: s)
      |> Repo.all()
      |> Enum.flat_map(fn rollout_server ->
        case server_gate_failure(rollout_server) do
          nil -> []
          {severity, reason} -> [{severity, gate_failure_details(rollout_server, reason)}]
        end
      end)

    # A critical signal (memory pressure) pauses immediately even when
    # another server merely fails the soak, so scan all failures before
    # picking.
    Enum.find(failures, &match?({:critical, _}, &1)) || List.first(failures)
  end

  defp gate_failure_details(rollout_server, reason) do
    %{
      server_id: rollout_server.kura_server_id,
      region: rollout_server.kura_server.region,
      wave: rollout_server.wave,
      signal: reason
    }
  end

  defp server_gate_failure(%RolloutServer{soak_eligible: true} = rollout_server) do
    case Provisioner.rollout_health(rollout_server.kura_server) do
      {:ok, health} when is_map(health) -> health_gate_failure(rollout_server, health)
      {:ok, nil} -> {:unhealthy, :health_unavailable}
      {:error, _reason} -> {:unhealthy, :health_unreadable}
    end
  end

  # Ungated servers were already unhealthy before their wave scheduled,
  # so absolute and comparative soak conditions would blame the new
  # image for pre-existing sickness — but critical memory pressure is a
  # safety stop, not a comparison, and an unreadable aggregate simply
  # cannot veto here (these servers are what the gate must never stand
  # in front of).
  defp server_gate_failure(%RolloutServer{soak_eligible: false} = rollout_server) do
    case Provisioner.rollout_health(rollout_server.kura_server) do
      {:ok, %{memory_pressure_state: pressure}} when pressure >= 2 -> {:critical, :memory_pressure_critical}
      _ -> nil
    end
  end

  defp health_gate_failure(rollout_server, health) do
    rollout_server
    |> gate_checks(health)
    |> Enum.find_value(fn {failed?, failure} -> if failed?, do: failure end)
  end

  # Ordered so the hard signal (critical memory pressure) wins over
  # soak-clock resets when several conditions fail at once.
  defp gate_checks(rollout_server, health) do
    outbox_threshold =
      case rollout_server.baseline_outbox_messages do
        nil -> nil
        baseline -> baseline + max(ceil(baseline / 10), @outbox_regression_floor)
      end

    [
      {health.memory_pressure_state >= 2, {:critical, :memory_pressure_critical}},
      {not fresh_sample?(health), {:unhealthy, :sample_stale}},
      {health.sampled_pods < health.expected_pods, {:unhealthy, :pods_unsampled}},
      {not health.ready, {:unhealthy, :not_ready}},
      {not health.serving, {:unhealthy, :not_serving}},
      {not health.generation_consistent, {:unhealthy, :generation_skew}},
      {health.bootstrap_inflight_peers > 0, {:unhealthy, :bootstrap_in_flight}},
      {counter_regressed?(health.outbox_messages, outbox_threshold), {:unhealthy, :outbox_regressed}},
      {counter_grew?(health.fd_timeout_count, rollout_server.baseline_fd_timeout_count),
       {:unhealthy, :fd_timeouts_regressed}},
      {counter_grew?(health.peer_connection_failures, rollout_server.baseline_peer_connection_failures),
       {:unhealthy, :peer_connection_failures_regressed}}
    ]
  end

  defp counter_regressed?(_current, nil), do: false
  defp counter_regressed?(current, threshold), do: current > threshold

  # Counter resets (controller restart, pod replacement) read as a
  # decrease; a decrease is never growth, so it passes — matching the
  # standalone gate's clamping.
  defp counter_grew?(_current, nil), do: false
  defp counter_grew?(current, baseline), do: current > baseline

  defp complete_wave(rollout) do
    record_event(rollout, "wave_completed", "system", nil, %{wave: rollout.current_wave})

    rollout =
      rollout
      |> Rollout.update_changeset(%{
        current_wave: rollout.current_wave + 1,
        wave_started_at: nil,
        wave_healthy_since: nil
      })
      |> Repo.update!()

    broadcast()

    # Open the next wave in the same tick: the soak already held, so
    # deferring its scheduling to the next tick would only add latency.
    # The chain is bounded — a freshly scheduled wave cannot complete
    # before its own convergence and soak.
    advance_progressive(rollout)
  end

  defp complete_rollout(rollout) do
    rollout =
      rollout
      |> Rollout.update_changeset(%{status: :completed, completed_at: now()})
      |> Repo.update!()

    record_event(rollout, "completed", "system", nil, %{})
    Notifier.notify(:completed, rollout, %{})
    rollout
  end

  defp pause_rollout(rollout, {reason, details}) do
    rollout =
      rollout
      |> Rollout.update_changeset(%{
        status: :paused,
        paused_at: now(),
        wave_healthy_since: nil,
        pause_reason: Atom.to_string(reason)
      })
      |> Repo.update!()

    metadata = Map.merge(%{wave: rollout.current_wave, signal: reason}, details)
    record_event(rollout, "paused", "gate", nil, metadata)
    Notifier.notify(:paused, rollout, metadata)
    :ok
  end

  ## Operator verbs

  @doc """
  Manual pause, for the case where a human sees something the gate does
  not. A paused rollout schedules nothing further.
  """
  def pause(%Rollout{} = rollout, actor, reason) when is_binary(actor) do
    with_locked_rollout(rollout.id, fn
      %Rollout{status: :running} = rollout ->
        rollout =
          rollout
          |> Rollout.update_changeset(%{
            status: :paused,
            paused_at: now(),
            wave_healthy_since: nil,
            pause_reason: "manual"
          })
          |> Repo.update!()

        record_event(rollout, "paused", actor, reason, %{wave: rollout.current_wave, manual: true})
        Notifier.notify(:paused, rollout, %{actor: actor, reason: reason, manual: true})
        {:ok, rollout}

      rollout ->
        {:error, {:not_pausable, rollout.status}}
    end)
  end

  @doc """
  Resume means re-attempt, not re-evaluate: the current attempt's open
  deployments for non-converged servers are cancelled, fresh deployments
  are minted for every non-converged server — including those whose
  previous attempt failed — baselines are re-captured, and the wave
  re-enters its gate. Without this, a wave that failed for an
  infrastructure reason would stay a dead end until an unrelated Kura
  release re-triggered scheduling.
  """
  def resume(%Rollout{} = rollout, actor, reason) when is_binary(actor) do
    with_locked_rollout(rollout.id, fn
      %Rollout{status: :paused} = rollout ->
        reattempt_non_converged(rollout)

        rollout =
          rollout
          |> Rollout.update_changeset(%{
            status: :running,
            paused_at: nil,
            pause_reason: nil,
            wave_started_at: now(),
            wave_healthy_since: nil
          })
          |> Repo.update!()

        record_event(rollout, "resumed", actor, reason, %{wave: rollout.current_wave})
        Notifier.notify(:resumed, rollout, %{actor: actor, reason: reason})
        {:ok, rollout}

      rollout ->
        {:error, {:not_resumable, rollout.status}}
    end)
  end

  @doc """
  Flips the rollout to all-at-once fan-out (today's behavior), at any
  point mid-flight, so progressive pacing never stands between an
  incident and its fix. Expediting a paused rollout also resumes it,
  re-attempting failed deployments. Always an explicit act; the event
  records actor, reason, source and target tags, and whether the target
  previously completed in this environment.
  """
  def expedite(%Rollout{} = rollout, actor, reason) when is_binary(actor) do
    with_locked_rollout(rollout.id, fn
      %Rollout{status: status} = rollout when status in [:running, :paused] ->
        if status == :paused, do: reattempt_non_converged(rollout)

        rollout =
          rollout
          |> Rollout.update_changeset(%{
            status: :running,
            mode: :expedited,
            paused_at: nil,
            pause_reason: nil,
            wave_healthy_since: nil
          })
          |> Repo.update!()

        metadata = %{
          source_tag: rollout.baseline_image_tag,
          target_tag: rollout.image_tag,
          previously_completed: previously_completed?(rollout.image_tag)
        }

        record_event(rollout, "expedited", actor, reason, metadata)
        Notifier.notify(:expedited, rollout, Map.put(metadata, :actor, actor))
        {:ok, rollout}

      rollout ->
        {:error, {:not_expeditable, rollout.status}}
    end)
  end

  @doc """
  Terminal stop: cancels the rollout's open deployments and schedules
  nothing further. Rolling back stays a separate operator decision
  (re-pin the previous tag and expedite).
  """
  def abort(%Rollout{} = rollout, actor, reason) when is_binary(actor) do
    with_locked_rollout(rollout.id, fn
      %Rollout{status: status} = rollout when status in [:running, :paused] ->
        rollout = rollout |> Rollout.update_changeset(%{status: :aborted}) |> Repo.update!()
        cancel_open_rollout_deployments(rollout, "rollout aborted by #{actor}")
        record_event(rollout, "aborted", actor, reason, %{wave: rollout.current_wave})
        Notifier.notify(:aborted, rollout, %{actor: actor, reason: reason})
        {:ok, rollout}

      rollout ->
        {:error, {:not_abortable, rollout.status}}
    end)
  end

  defp reattempt_non_converged(rollout) do
    RolloutServer
    |> join(:inner, [rs], s in assoc(rs, :kura_server))
    |> where([rs], rs.kura_rollout_id == ^rollout.id and is_nil(rs.converged_at))
    |> where([_rs, s], s.status not in ^@terminal_server_statuses)
    |> preload([rs, s], kura_server: s)
    |> Repo.all()
    |> Enum.each(fn rollout_server ->
      cancel_open_deployment(rollout_server, "superseded by rollout resume re-attempt")

      server = rollout_server.kura_server
      {baseline, soak_eligible} = capture_baseline(server)

      # nil when another (non-rollout) deployment still holds the
      # server's open slot; mint_missing_deployments retries next tick.
      deployment_id = mint_deployment(rollout, server)

      {:ok, _} =
        rollout_server
        |> RolloutServer.update_changeset(%{
          attempt: rollout_server.attempt + 1,
          soak_eligible: soak_eligible,
          baseline_outbox_messages: baseline[:outbox_messages],
          baseline_fd_timeout_count: baseline[:fd_timeout_count],
          baseline_peer_connection_failures: baseline[:peer_connection_failures],
          baseline_captured_at: now(),
          deployment_id: deployment_id
        })
        |> Repo.update()
    end)
  end

  defp cancel_open_deployment(%RolloutServer{deployment_id: nil}, _message), do: :ok

  defp cancel_open_deployment(%RolloutServer{deployment_id: deployment_id}, message) do
    case Repo.get(Deployment, deployment_id) do
      %Deployment{status: status} = deployment when status in @open_deployment_statuses ->
        {:ok, _} = Kura.mark_cancelled(deployment, message)
        :ok

      _ ->
        :ok
    end
  end

  # Covers both deployments this rollout minted (kura_rollout_id) and
  # open deployments it adopted (a server created mid-rollout whose
  # initial install already carried the target tag) — adopted rows keep
  # their original attribution but their lifecycle belongs to the
  # rollout, so an abort or supersede must stop them too.
  defp cancel_open_rollout_deployments(rollout, message) do
    adopted =
      RolloutServer
      |> where([rs], rs.kura_rollout_id == ^rollout.id and not is_nil(rs.deployment_id))
      |> select([rs], rs.deployment_id)

    Deployment
    |> where([d], d.status in ^@open_deployment_statuses)
    |> where([d], d.kura_rollout_id == ^rollout.id or d.id in subquery(adopted))
    |> Repo.all()
    |> Enum.each(fn deployment ->
      {:ok, _} = Kura.mark_cancelled(deployment, message)
    end)
  end

  ## Shared plumbing

  defp with_locked_rollout(rollout_id, fun) do
    {:ok, result} =
      Repo.transaction(fn ->
        Rollout
        |> where([r], r.id == ^rollout_id)
        |> lock("FOR UPDATE")
        |> Repo.one!()
        |> fun.()
      end)

    result
  end

  defp record_event(rollout, action, actor, reason, metadata) do
    {:ok, _event} =
      %{
        kura_rollout_id: rollout.id,
        action: action,
        actor: actor,
        reason: reason,
        metadata: metadata
      }
      |> RolloutEvent.create_changeset()
      |> Repo.insert()

    broadcast()
    :ok
  end

  @doc """
  Subscribe to rollout state changes. Messages arrive as
  `{:kura_rollouts, :updated}`; subscribers re-read the state they need.
  """
  def subscribe do
    PubSub.subscribe(@pubsub, @topic)
  end

  defp broadcast do
    PubSub.broadcast(@pubsub, @topic, {:kura_rollouts, :updated})
  end

  defp now, do: DateTime.truncate(DateTime.utc_now(), :second)
end
