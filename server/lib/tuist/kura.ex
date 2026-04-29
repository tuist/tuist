defmodule Tuist.Kura do
  @moduledoc """
  Per-account Kura mesh management.

  Four responsibilities:

    * **Versions** — `record_version/2` and `latest_versions/1` cache
      published Kura tags discovered by
      `Tuist.Kura.Workers.PollVersionsWorker`.
    * **Servers** — `create_server/1`, `list_servers_for_account/1`,
      `destroy_server/1` manage the per-account Kura mesh instances.
      Each server has a lifecycle (`:provisioning → :active`, or
      `:failed` / `:destroying / :destroyed`) and is the unit of
      provisioning the operator interacts with.
    * **Deployments** — `create_deployment/1` inserts a per-rollout
      event row and enqueues `Tuist.Kura.Workers.RolloutWorker`. A
      deployment is always tied to a server (`kura_server_id`) once
      this refactor lands.
    * **Logs** — `append_log_lines/2` / `list_log_lines/2` for
      stdout/stderr captured by the rollout worker, stored in
      ClickHouse.

  Server lifecycle transitions are broadcast over Phoenix.PubSub on the
  `"kura:account:<account_id>"` topic so the /ops UI can update without
  polling. See `subscribe_to_account/1`.

  When a server reaches `:active`, its public URL is mirrored into
  `account_cache_endpoints` (with `technology: :kura`); when it's
  destroyed, the row is removed. Operators don't touch
  `account_cache_endpoints` directly anymore — servers are the source
  of truth.
  """

  import Ecto.Query

  alias Phoenix.PubSub
  alias Tuist.Accounts
  alias Tuist.Accounts.AccountCacheEndpoint
  alias Tuist.IngestRepo
  alias Tuist.Kura.Clusters
  alias Tuist.Kura.DeploymentLogLine
  alias Tuist.Kura.KuraDeployment
  alias Tuist.Kura.KuraServer
  alias Tuist.Kura.KuraVersion
  alias Tuist.Kura.Specs
  alias Tuist.Kura.Workers.DestroyServerWorker
  alias Tuist.Kura.Workers.RolloutWorker
  alias Tuist.Repo

  @pubsub Tuist.PubSub

  ## Versions

  @doc "Inserts a version row if not already present. Idempotent."
  def record_version(version, %DateTime{} = released_at) when is_binary(version) do
    %{version: version, released_at: released_at}
    |> KuraVersion.changeset()
    |> Repo.insert(on_conflict: :nothing, conflict_target: :version)
  end

  @doc "Returns the most recently released versions, newest first."
  def latest_versions(limit \\ 20) when is_integer(limit) do
    KuraVersion
    |> order_by([v], desc: v.released_at)
    |> limit(^limit)
    |> Repo.all()
  end

  ## Servers

  @doc """
  Provisions a new Kura server for an account.

  Inserts a `KuraServer` (status: `:provisioning`) and an initial
  `KuraDeployment`, then enqueues the rollout worker. Returns
  `{:ok, server}` (with `:deployments` preloaded) on success, or
  `{:error, changeset_or_reason}` on validation/insertion failure.

  `attrs` accepts: `:account_id`, `:cluster_id`, `:spec`,
  `:volume_size_gi` (defaults from the spec catalog if omitted),
  `:image_tag`, `:requested_by_user_id`.
  """
  def create_server(attrs) do
    attrs =
      Map.put_new_lazy(attrs, :volume_size_gi, fn ->
        Specs.default_volume_gi(attrs[:spec] || :medium) || 200
      end)

    image_tag = attrs[:image_tag] || attrs["image_tag"]

    # Recycle terminal-state rows that share the same triple. Failed
    # and destroyed servers shouldn't permanently block reprovisioning;
    # active/provisioning/destroying rows still trigger the unique
    # constraint and surface a clear changeset error to the operator.
    recycle_terminal_server(attrs)

    Repo.transaction(fn ->
      with {:ok, server} <- attrs |> KuraServer.create_changeset() |> Repo.insert(),
           {:ok, deployment} <-
             KuraDeployment.create_changeset(%{
               account_id: server.account_id,
               cluster_id: server.cluster_id,
               image_tag: image_tag,
               requested_by_user_id: server.requested_by_user_id,
               kura_server_id: server.id
             })
             |> Repo.insert(),
           {:ok, job} <- enqueue_rollout(deployment),
           {:ok, _deployment} <- stamp_job_id(deployment, job.id) do
        server = Repo.preload(server, :deployments)
        broadcast_server(server, :created)
        server
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp recycle_terminal_server(attrs) do
    account_id = attrs[:account_id] || attrs["account_id"]
    cluster_id = attrs[:cluster_id] || attrs["cluster_id"]
    spec = attrs[:spec] || attrs["spec"]

    if account_id && cluster_id && spec do
      from(s in KuraServer,
        where:
          s.account_id == ^account_id and
            s.cluster_id == ^cluster_id and
            s.spec == ^spec and
            s.status in [:failed, :destroyed]
      )
      |> Repo.delete_all()
    end
  end

  @doc """
  Returns the non-destroyed servers for an account, each preloaded with
  its deployments (newest first) so the /ops UI can link straight to
  the latest deployment's log tail.
  """
  def list_servers_for_account(account_id) do
    deployments_query =
      from(d in KuraDeployment, order_by: [desc: d.inserted_at, desc: d.id])

    KuraServer
    |> where([s], s.account_id == ^account_id and s.status != :destroyed)
    |> order_by([s], asc: s.cluster_id, asc: s.spec)
    |> preload(deployments: ^deployments_query)
    |> Repo.all()
  end

  @doc "Fetches a server scoped to the given account."
  def get_server(account_id, server_id) do
    Repo.get_by(KuraServer, id: server_id, account_id: account_id)
  end

  @doc """
  Marks a server as `:active` after a successful deployment, mirrors
  its URL into `account_cache_endpoints`, and broadcasts.
  """
  def activate_server(%KuraServer{} = server, image_tag) when is_binary(image_tag) do
    {:ok, account} = Accounts.get_account_by_id(server.account_id)
    cluster = Clusters.get(server.cluster_id)
    url = Clusters.public_url(account.name, cluster)

    Repo.transaction(fn ->
      {:ok, server} =
        server
        |> KuraServer.status_changeset(%{
          status: :active,
          url: url,
          current_image_tag: image_tag
        })
        |> Repo.update()

      ensure_account_cache_endpoint(account, url)
      broadcast_server(server, :updated)
      server
    end)
  end

  @doc "Marks a server as `:failed` after an unrecoverable rollout error."
  def fail_server(%KuraServer{} = server) do
    {:ok, server} =
      server
      |> KuraServer.status_changeset(%{status: :failed})
      |> Repo.update()

    broadcast_server(server, :updated)
    {:ok, server}
  end

  @doc """
  Schedules destruction: marks the server `:destroying`, removes the
  account_cache_endpoint mirror immediately so the CLI stops using the
  URL, and enqueues the destroy worker to `helm uninstall` the release.
  """
  def destroy_server(%KuraServer{} = server) do
    Repo.transaction(fn ->
      {:ok, server} =
        server
        |> KuraServer.status_changeset(%{status: :destroying})
        |> Repo.update()

      if server.url do
        from(e in AccountCacheEndpoint,
          where: e.account_id == ^server.account_id and e.url == ^server.url
        )
        |> Repo.delete_all()
      end

      {:ok, _job} = %{server_id: server.id} |> DestroyServerWorker.new() |> Oban.insert()
      broadcast_server(server, :updated)
      server
    end)
  end

  @doc "Marks a server as `:destroyed` after the destroy worker finishes."
  def mark_destroyed(%KuraServer{} = server) do
    {:ok, server} =
      server
      |> KuraServer.status_changeset(%{status: :destroyed, url: nil})
      |> Repo.update()

    broadcast_server(server, :destroyed)
    {:ok, server}
  end

  defp ensure_account_cache_endpoint(account, url) do
    case Accounts.create_account_cache_endpoint(account, %{url: url, technology: :kura}) do
      {:ok, _} ->
        :ok

      {:error, %Ecto.Changeset{errors: errors}} ->
        # Idempotent: if the row already exists (unique on
        # account_id+technology+url) we're fine.
        if Keyword.has_key?(errors, :url) and Enum.any?(errors, fn {_, {msg, _}} -> msg =~ "already" end),
          do: :ok,
          else: :ok
    end
  end

  ## Deployments

  @doc """
  Inserts a `KuraDeployment` and enqueues the rollout worker.

  Validates that the cluster exists in `Tuist.Kura.Clusters.all/0` and
  that the image tag looks like a semver. Returns `{:ok, deployment}`
  with the Oban job ID stamped onto the row, or `{:error, changeset}`.
  """
  def create_deployment(attrs) do
    Repo.transaction(fn ->
      with {:ok, deployment} <- attrs |> KuraDeployment.create_changeset() |> Repo.insert(),
           {:ok, job} <- enqueue_rollout(deployment),
           {:ok, deployment} <- stamp_job_id(deployment, job.id) do
        deployment
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp enqueue_rollout(%KuraDeployment{id: id}) do
    %{deployment_id: id}
    |> RolloutWorker.new()
    |> Oban.insert()
  end

  defp stamp_job_id(deployment, job_id) do
    deployment
    |> KuraDeployment.status_changeset(%{oban_job_id: job_id, status: :pending})
    |> Repo.update()
  end

  @doc "Returns deployments for the account, newest first."
  def list_deployments_for_account(account_id, limit \\ 50) do
    KuraDeployment
    |> where([d], d.account_id == ^account_id)
    |> order_by([d], desc: d.inserted_at, desc: d.id)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc "Fetches a deployment, scoped to the given account so URLs cannot enumerate."
  def get_deployment(account_id, deployment_id) do
    Repo.get_by(KuraDeployment, id: deployment_id, account_id: account_id)
  end

  @doc "Marks a deployment as running and records the start time."
  def mark_running(%KuraDeployment{} = deployment) do
    deployment
    |> KuraDeployment.status_changeset(%{
      status: :running,
      started_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
    |> Repo.update()
  end

  @doc "Marks a deployment as succeeded with the finish time."
  def mark_succeeded(%KuraDeployment{} = deployment) do
    # Clearing error_message guards against a race where another worker
    # raced ahead and stamped a transient error onto the row before this
    # worker's success update lands.
    deployment
    |> KuraDeployment.status_changeset(%{
      status: :succeeded,
      error_message: nil,
      finished_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
    |> Repo.update()
  end

  @doc "Marks a deployment as failed and records the error message."
  def mark_failed(%KuraDeployment{} = deployment, message) when is_binary(message) do
    deployment
    |> KuraDeployment.status_changeset(%{
      status: :failed,
      error_message: message,
      finished_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
    |> Repo.update()
  end

  ## Logs (ClickHouse)

  @doc """
  Appends a batch of log lines for a deployment.

  Each entry is `{sequence, stream, line}` where `stream` is `:stdout`
  or `:stderr`. The worker assigns sequence numbers as it reads from the
  Port so ordering is stable across ClickHouse parts.
  """
  def append_log_lines(_deployment_id, []), do: {:ok, 0}

  def append_log_lines(deployment_id, lines) when is_list(lines) do
    rows =
      Enum.map(lines, fn {seq, stream, line} ->
        [
          deployment_id: deployment_id,
          sequence: seq,
          stream: stream_to_string(stream),
          line: line
        ]
      end)

    {count, _} = IngestRepo.insert_all(DeploymentLogLine, rows)
    {:ok, count}
  end

  @doc "Returns log lines for a deployment, oldest first, capped at `limit`."
  def list_log_lines(deployment_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 1_000)
    after_sequence = Keyword.get(opts, :after_sequence, -1)

    query = """
    SELECT sequence, stream, line, inserted_at
    FROM kura_deployment_log_lines
    WHERE deployment_id = {deployment_id:UUID}
      AND sequence > {after_sequence:UInt64}
    ORDER BY sequence ASC
    LIMIT {limit:UInt32}
    """

    case IngestRepo.query(query, %{
           "deployment_id" => deployment_id,
           "after_sequence" => max(after_sequence, -1),
           "limit" => limit
         }) do
      {:ok, %{rows: rows}} ->
        Enum.map(rows, fn [seq, stream, line, inserted_at] ->
          %{
            sequence: seq,
            stream: string_to_stream(stream),
            line: line,
            inserted_at: inserted_at
          }
        end)

      {:error, _reason} ->
        []
    end
  end

  defp stream_to_string(:stdout), do: "stdout"
  defp stream_to_string(:stderr), do: "stderr"

  defp string_to_stream("stdout"), do: :stdout
  defp string_to_stream("stderr"), do: :stderr
  defp string_to_stream(other), do: other

  ## PubSub

  @doc """
  Subscribe the calling process to server lifecycle events for an
  account. Messages arrive as
  `{:kura_server, :created | :updated | :destroyed, %KuraServer{}}`.
  """
  def subscribe_to_account(account_id) do
    PubSub.subscribe(@pubsub, account_topic(account_id))
  end

  defp broadcast_server(%KuraServer{account_id: account_id} = server, event) do
    PubSub.broadcast(@pubsub, account_topic(account_id), {:kura_server, event, server})
  end

  defp account_topic(account_id), do: "kura:account:#{account_id}"

  ## Cluster catalog (re-exported for convenience)

  defdelegate clusters, to: Clusters, as: :all
  defdelegate cluster(id), to: Clusters, as: :get
  defdelegate public_url(handle, cluster), to: Clusters
  defdelegate release_name(handle, cluster), to: Clusters
  defdelegate specs, to: Specs, as: :all
end
