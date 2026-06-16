defmodule Tuist.Kura.Reconciler do
  @moduledoc """
  Primary reconciliation loop for Kura servers.

  Postgres owns intent (`kura_servers` rows for which regions a server
  should exist, `kura_deployments` for the deployment history and
  audit) plus the latest released Kura runtime image tag. The backing
  `KuraInstance`, owned by the Go controller, owns observed runtime
  state.

  `kura_servers.status` is a **projection of observed state**, not an
  independently-mutated state machine. Each tick:

    1. schedule runtime-image drift for active servers,
    2. finalise destroys after the custom resource disappears,
    3. apply open deployments (the rollout fast path), and
    4. project every other present-intent server: observe the backing
       `KuraInstance`, record the observation (`observed_image_tag` /
       `last_observed_at`), and re-derive `status` from
       `(latest deployment intent, observed image, endpoint readiness)`.

  Because step 4 re-derives `status` from observation every tick,
  `:failed` is never a sticky terminal sink: a server whose backing
  resource recovers and reports the intended image with a serving
  endpoint heals back to `:active` in place, with no new deployment row
  and no manifest re-apply, so a still-serving endpoint is never
  trampled. The desired image is the latest deployment's image (the
  recorded intent), so a rollout the controller eventually applied
  heals even though it differs from what the server used to serve.
  `Kura.fail_server/1` is only a same-tick fast path for the UI; this
  projection is the authority. Re-rolling onto a different image stays
  the operator's explicit retry/destroy decision.

  Endpoint readiness is end-to-end: `Kura.activate_server/2` only marks
  a server `:active` after the regional public endpoint answers `/up`.
  The controller's `status.phase` attests workload readiness only, not
  public reachability, so the projection deliberately keeps the live
  probe as the readiness authority.

  User actions only mutate Postgres intent. If a BEAM dies mid-action,
  this loop observes the same rows on the next tick and converges again.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  import Ecto.Query

  alias Tuist.Kura
  alias Tuist.Kura.Deployment
  alias Tuist.Kura.Provisioner
  alias Tuist.Kura.Server
  alias Tuist.Repo

  require Logger

  @deployment_statuses [:pending, :running]
  # Hard ceiling on how much converge work the reconciler does in one
  # tick. The cron fires every 30 s; bigger fan-outs are rare enough in
  # practice that one or two extra ticks are fine, and the ceiling
  # guards against a runaway query if a regression ever leaks
  # `:running` rows.
  @reconcile_batch_size 200

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    reconcile()
  end

  def reconcile do
    # Converge runner-cache nodes with runner enablement before the rest
    # of the loop so a freshly enabled account's node enters the normal
    # provisioning/observation path within the same tick.
    Tuist.Kura.RunnerCache.reconcile()

    with {:ok, scheduled} <- Kura.schedule_runtime_image_deployments() do
      log_scheduled_deployments(scheduled)
      reconcile_destroying_servers()
      handled = reconcile_deployments()
      reconcile_observed_servers(handled)
    end
  end

  defp log_scheduled_deployments([]), do: :ok

  defp log_scheduled_deployments(deployments) do
    Logger.info("[Kura.Reconciler] scheduled #{length(deployments)} runtime image deployment(s)")
    :ok
  end

  defp reconcile_destroying_servers do
    Server
    |> where([s], s.status == :destroying)
    |> order_by([s], asc: s.updated_at, asc: s.id)
    |> limit(^@reconcile_batch_size)
    |> Repo.all()
    |> Enum.each(&reconcile_destroying_server/1)

    :ok
  end

  defp reconcile_destroying_server(%Server{} = server) do
    case Provisioner.current_image_tag(server) do
      {:error, :not_found} ->
        {:ok, _} = Kura.mark_destroyed(server)
        :ok

      {:ok, _image_tag} ->
        case Provisioner.destroy(server) do
          :ok ->
            :ok

          {:error, reason} ->
            Logger.warning("[Kura.Reconciler] destroy failed for server #{server.id}: #{inspect(reason)}")
            :ok
        end

      {:error, reason} ->
        Logger.warning("[Kura.Reconciler] could not observe destroying server #{server.id}: #{inspect(reason)}")
        :ok
    end
  end

  # Returns the set of server ids whose open deployment was processed
  # this tick. The projection pass skips them so a server is observed
  # at most once per tick (keeps the rollout fast path and the
  # projection from racing or double-probing the same server).
  defp reconcile_deployments do
    MapSet.new(latest_open_deployments(), fn deployment ->
      reconcile_deployment(deployment)
      deployment.kura_server_id
    end)
  end

  defp latest_open_deployments do
    Deployment
    |> where([d], d.status in ^@deployment_statuses)
    |> join(:inner, [d], s in assoc(d, :kura_server))
    |> order_by([d, _s], desc: d.inserted_at, desc: d.id)
    |> limit(^@reconcile_batch_size)
    |> preload([_d, s], kura_server: {s, :account})
    |> Repo.all()
    |> Enum.uniq_by(& &1.kura_server_id)
  end

  defp reconcile_deployment(%Deployment{kura_server: %Server{status: status} = server} = deployment)
       when status in [:destroying, :destroyed] do
    cancel(deployment, "server #{server.id} is #{server.status}; skipping rollout")
  end

  defp reconcile_deployment(%Deployment{kura_server: %Server{} = server} = deployment) do
    case Provisioner.current_image_tag(server) do
      {:ok, image_tag} when image_tag == deployment.image_tag ->
        activate_and_mark_succeeded(deployment, server)

      {:ok, _other_image_tag} ->
        apply_deployment(deployment, server)

      {:error, :not_found} ->
        apply_deployment(deployment, server)

      {:error, reason} ->
        fail(deployment, server, reason)
    end
  end

  defp activate_and_mark_succeeded(%Deployment{} = deployment, %Server{} = server) do
    with {:ok, deployment} <- ensure_running(deployment) do
      case Kura.activate_server(server, deployment.image_tag) do
        {:ok, _server} ->
          {:ok, _deployment} = Kura.mark_succeeded(deployment)
          :ok

        {:error, status} when status in [:server_destroying, :server_destroyed] ->
          cancel(deployment, "server #{server.id} became #{server_status(status)} during rollout; skipping activation")

        {:error, {:public_host_not_resolvable, host, reason}} ->
          # external-dns has not propagated yet. Leave the deployment in
          # `:running` so the next reconciler tick retries instead of
          # marking the server failed for what's a benign delay.
          Logger.info("[Kura.Reconciler] waiting on DNS for server #{server.id} (#{host}): #{inspect(reason)}")

          :ok

        {:error, {:public_endpoint_not_ready, host, reason}} ->
          Logger.info(
            "[Kura.Reconciler] waiting on public endpoint for server #{server.id} (#{host}): #{inspect(reason)}"
          )

          :ok

        {:error, :node_port_endpoint_not_ready} ->
          # The controller has not yet observed the full node-port
          # chain (Service ports allocated, primary pod placed on a
          # labeled node). Benign startup delay, same as DNS.
          Logger.info("[Kura.Reconciler] waiting on node-port endpoint for server #{server.id}")

          :ok

        {:error, reason} ->
          fail(deployment, server, reason)
      end
    end
  end

  defp apply_deployment(%Deployment{} = deployment, %Server{} = server) do
    with {:ok, deployment} <- ensure_running(deployment) do
      inputs = %{
        image_tag: deployment.image_tag,
        account: server.account,
        server: server
      }

      case Provisioner.rollout(server, inputs) do
        :ok ->
          :ok

        {:error, :not_found} ->
          fail(deployment, server, "region #{server.region} is no longer in the catalog")

        {:error, reason} ->
          fail(deployment, server, reason)
      end
    end
  end

  defp ensure_running(%Deployment{status: :running} = deployment), do: {:ok, deployment}
  defp ensure_running(%Deployment{} = deployment), do: Kura.mark_running(deployment)

  @present_intent_statuses [:provisioning, :active, :failed]
  @open_deployment_statuses [:pending, :running]

  # Projects observed cluster state onto present-intent servers the
  # deployment loop did not handle this tick: failed servers heal,
  # drifted ones surface the drift. Bounded by the same converge
  # ceiling as the rest of the loop; the rest is picked up next tick.
  defp reconcile_observed_servers(handled_server_ids) do
    servers =
      Server
      |> where([s], s.status in ^@present_intent_statuses)
      |> order_by([s], asc: s.updated_at, asc: s.id)
      |> limit(^@reconcile_batch_size)
      |> preload(:account)
      |> Repo.all()
      |> Enum.reject(&MapSet.member?(handled_server_ids, &1.id))

    latest = latest_deployments(Enum.map(servers, & &1.id))

    Enum.each(servers, &project_server(&1, Map.get(latest, &1.id)))

    :ok
  end

  # Newest deployment per server in one query; the
  # (kura_server_id, inserted_at) index backs the DISTINCT ON.
  defp latest_deployments([]), do: %{}

  defp latest_deployments(server_ids) do
    Deployment
    |> where([d], d.kura_server_id in ^server_ids)
    |> distinct([d], d.kura_server_id)
    |> order_by([d], asc: d.kura_server_id, desc: d.inserted_at, desc: d.id)
    |> Repo.all()
    |> Map.new(&{&1.kura_server_id, &1})
  end

  defp project_server(%Server{}, nil), do: :ok

  defp project_server(%Server{}, %Deployment{status: status}) when status in @open_deployment_statuses do
    # Open deployment not in this tick's batch (ceiling/uniq). The
    # rollout fast path owns it; don't race.
    :ok
  end

  defp project_server(%Server{} = server, %Deployment{image_tag: desired, status: latest_status}) do
    case Provisioner.current_image_tag(server) do
      {:ok, observed} when observed == desired ->
        reconcile_manifest_revision(server, desired)

      {:ok, observed} ->
        record(server, derived_status(server, latest_status), observed, now())

      {:error, :not_found} when latest_status == :succeeded ->
        apply_current_manifest(server, desired)

      {:error, :not_found} ->
        record(server, derived_status(server, latest_status), nil, now())

      {:error, reason} ->
        Logger.warning("[Kura.Reconciler] could not observe server #{server.id}: #{inspect(reason)}")
        :ok
    end
  end

  defp reconcile_manifest_revision(%Server{} = server, desired) do
    case {Provisioner.manifest_revision(server), Provisioner.current_manifest_revision(server)} do
      {{:ok, nil}, _} ->
        converge(server, desired)

      {{:ok, desired_revision}, {:ok, desired_revision}} ->
        converge(server, desired)

      {{:ok, _desired_revision}, {:ok, _observed_revision}} ->
        apply_current_manifest(server, desired)

      {{:error, reason}, _} ->
        Logger.warning(
          "[Kura.Reconciler] could not resolve desired manifest revision for server #{server.id}: #{inspect(reason)}"
        )

        converge(server, desired)

      {_, {:error, reason}} ->
        Logger.warning(
          "[Kura.Reconciler] could not observe manifest revision for server #{server.id}: #{inspect(reason)}"
        )

        converge(server, desired)
    end
  end

  defp apply_current_manifest(%Server{} = server, image_tag) do
    inputs = %{
      image_tag: image_tag,
      account: server.account,
      server: server
    }

    case Provisioner.rollout(server, inputs) do
      :ok ->
        converge(server, image_tag)

      {:error, reason} ->
        Logger.warning("[Kura.Reconciler] could not re-apply manifest for server #{server.id}: #{inspect(reason)}")
        converge(server, image_tag)
    end
  end

  defp converge(%Server{} = server, desired) do
    if converged?(server, desired) and endpoint_in_sync?(server) do
      refresh_node_port_url(server)
    else
      do_converge(server, desired)
    end
  end

  # A converged node-port server still needs its dispatch URL tracked:
  # the node-published endpoint moves with the primary pod. No-op for
  # cluster-DNS regions.
  defp refresh_node_port_url(%Server{} = server) do
    case Kura.refresh_private_server_url(server) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.warning(
          "[Kura.Reconciler] could not refresh node-port endpoint for server #{server.id}: #{inspect(reason)}"
        )

        :ok
    end
  end

  defp converged?(%Server{status: :active, current_image_tag: tag, observed_image_tag: tag}, tag), do: true

  defp converged?(%Server{}, _desired), do: false

  # The URL the region template renders can change without the image changing
  # (e.g. an environment-scoped public-host rename). `kura_servers.url` and the
  # `account_cache_endpoints` mirror are derived from it, but `converged?` only
  # tracks the image, so a healthy node would otherwise never re-derive them.
  # Treating a drifted URL as out of sync routes the server back through the
  # endpoint-gated `activate_server`, which re-probes the new host and rewrites
  # the mirror; once they match this is a no-op, so steady-state nodes are still
  # not re-written every tick. A non-binary render (e.g. unknown region) leaves
  # the existing `converged?` behaviour untouched.
  defp endpoint_in_sync?(%Server{url: url} = server) do
    case Provisioner.public_url(server.account, server) do
      ^url -> true
      rendered when is_binary(rendered) -> false
      _ -> true
    end
  end

  # Already active on the observed image: a no-op. Skip the write and
  # broadcast so a healthy server is not re-locked, re-written, and
  # pushed to every open settings LiveView every tick. Anything else
  # heals through the endpoint-gated activation.
  defp do_converge(%Server{} = server, desired) do
    case Kura.activate_server(server, desired) do
      {:ok, _server} ->
        Logger.info("[Kura.Reconciler] converged server #{server.id} to #{desired}")
        :ok

      {:error, status} when status in [:server_destroying, :server_destroyed] ->
        :ok

      {:error, {:public_host_not_resolvable, host, reason}} ->
        Logger.info("[Kura.Reconciler] waiting on DNS for server #{server.id} (#{host}): #{inspect(reason)}")
        record(server, server.status, desired, now())

      {:error, {:public_endpoint_not_ready, host, reason}} ->
        Logger.info("[Kura.Reconciler] waiting on public endpoint for server #{server.id} (#{host}): #{inspect(reason)}")

        record(server, server.status, desired, now())

      {:error, :node_port_endpoint_not_ready} ->
        Logger.info("[Kura.Reconciler] waiting on node-port endpoint for server #{server.id}")

        record(server, server.status, desired, now())

      {:error, reason} ->
        Logger.warning("[Kura.Reconciler] could not converge server #{server.id}: #{inspect(reason)}")
        record(server, server.status, desired, now())
    end
  end

  # A failed latest deployment projects to `:failed`; otherwise the
  # stored status stands, so a serving server is not flapped by a
  # transient observation gap.
  defp derived_status(%Server{}, :failed), do: :failed
  defp derived_status(%Server{status: status}, _latest_status), do: status

  defp record(%Server{} = server, status, observed_image_tag, observed_at) do
    attrs = %{status: status, observed_image_tag: observed_image_tag, last_observed_at: observed_at}

    case Kura.record_observation(server, attrs) do
      {:ok, _server} ->
        :ok

      {:error, reason} ->
        Logger.warning("[Kura.Reconciler] could not record observation for server #{server.id}: #{inspect(reason)}")

        :ok
    end
  end

  defp now, do: DateTime.truncate(DateTime.utc_now(), :second)

  defp cancel(deployment, message) do
    {:ok, _} = Kura.mark_cancelled(deployment, message)
    :ok
  end

  defp fail(deployment, server, reason) do
    message = if is_binary(reason), do: reason, else: inspect(reason)

    capture_deploy_failure(deployment, server, message)

    {:ok, _} = Kura.mark_failed(deployment, message)
    if server, do: Kura.fail_server(server)
    :ok
  end

  defp capture_deploy_failure(deployment, server, message) do
    Sentry.capture_message("Kura deploy failed",
      level: :error,
      extra: %{
        deployment_id: deployment.id,
        image_tag: deployment.image_tag,
        server_id: server && server.id,
        account_id: server && server.account_id,
        region: server && server.region,
        reason: message
      }
    )
  end

  defp server_status(:server_destroying), do: "destroying"
  defp server_status(:server_destroyed), do: "destroyed"
end
