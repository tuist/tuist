defmodule Tuist.Kura do
  @moduledoc """
  Per-account Kura server management.

  Identity is `(account, region)`: an account can light up Kura in as
  many regions as it needs, but only one server per region. `spec` is
  the capacity tier of that server.

  This context is provisioner-agnostic. The backend resource-allocation
  decisions live behind `Tuist.Kura.Provisioner`; here we ask for an
  opaque `provisioner_node_ref`, persist the server row, and kick off
  the install or update attempt that will make the server active.

  Lifecycle transitions broadcast on `"kura:account:<account_id>"` over
  Phoenix.PubSub. When a server reaches `:active` its public URL is
  mirrored into `account_cache_endpoints`; when it's destroyed the row
  is removed. `account_cache_endpoints` is now derived state — operators
  manage Kura through this module, not the endpoints table.
  """

  import Ecto.Query

  alias Phoenix.PubSub
  alias Tuist.Accounts
  alias Tuist.Accounts.AccountCacheEndpoint
  alias Tuist.GitHub.Releases
  alias Tuist.GitHub.Retry
  alias Tuist.IngestRepo
  alias Tuist.KeyValueStore
  alias Tuist.Kura.Deployment
  alias Tuist.Kura.DeploymentLogLine
  alias Tuist.Kura.Provisioner
  alias Tuist.Kura.Regions
  alias Tuist.Kura.Server
  alias Tuist.Kura.Specs
  alias Tuist.Kura.Workers.DestroyServerWorker
  alias Tuist.Kura.Workers.RolloutWorker
  alias Tuist.Repo

  require Logger

  @pubsub Tuist.PubSub
  @versions_cache_key [__MODULE__, "versions"]
  @versions_cache_ttl to_timeout(hour: 1)
  @versions_cache_opts [ttl: @versions_cache_ttl, persist_across_deployments: true]

  ## Versions

  @doc """
  Returns published Kura versions newest first.

  Reads through `Tuist.KeyValueStore` with a one-hour TTL: the first
  request after a cold start (or after the TTL expires) calls GitHub
  Releases; subsequent successful calls hit the in-memory or Redis
  cache. No background worker, no `kura_versions` table — the source
  of truth is the GitHub release feed.

  Returns a list of `%{version: String.t(), released_at: DateTime.t()}`
  maps, newest first, capped at `limit`. Returns `[]` when the
  GitHub call fails so callers (e.g. /ops version dropdown) degrade
  gracefully. Failed fetches are not cached, so a transient GitHub
  outage does not pin the UI to an empty result for the full TTL.
  """
  def latest_versions(limit \\ 20) when is_integer(limit) do
    versions =
      case KeyValueStore.get(@versions_cache_key, @versions_cache_opts) do
        nil ->
          case fetch_versions() do
            [] = versions ->
              versions

            versions ->
              _ = KeyValueStore.put(@versions_cache_key, versions, @versions_cache_opts)
              versions
          end

        versions ->
          versions
      end

    Enum.take(versions, limit)
  end

  defp fetch_versions do
    headers = [
      {"Accept", "application/vnd.github.v3+json"}
      | github_auth_headers()
    ]

    req_opts = [finch: Tuist.Finch, headers: headers] ++ Retry.retry_options()

    case Req.get(Releases.releases_url() <> "?per_page=100", req_opts) do
      {:ok, %Req.Response{status: 200, body: releases}} when is_list(releases) ->
        releases
        |> Enum.flat_map(&extract_kura_release/1)
        |> Enum.sort_by(& &1.released_at, {:desc, DateTime})

      {:ok, %Req.Response{status: status}} ->
        Logger.warning("[Kura.latest_versions] GitHub responded with #{status}")
        []

      {:error, reason} ->
        Logger.warning("[Kura.latest_versions] GitHub request failed: #{inspect(reason)}")
        []
    end
  end

  defp github_auth_headers do
    case Tuist.Environment.github_token_update_package_releases() do
      nil -> []
      token -> [{"Authorization", "Bearer #{token}"}]
    end
  end

  # Releases are tagged like `kura@0.5.2`. Returns a list with one entry
  # for matching tags, dropped otherwise.
  defp extract_kura_release(%{"tag_name" => "kura@" <> version, "published_at" => published_at}) do
    case DateTime.from_iso8601(published_at) do
      {:ok, dt, _offset} -> [%{version: version, released_at: DateTime.truncate(dt, :second)}]
      _ -> []
    end
  end

  defp extract_kura_release(_), do: []

  ## Servers

  @doc """
  Creates a new Kura server for an account in a region.

  Internally this asks the region's provisioner for an opaque ref,
  inserts a `Server` (status: `:provisioning`) and an initial
  `Deployment` row, and enqueues the worker that performs the first
  install. Returns `{:ok, server}` (deployment history preloaded) or
  `{:error, reason}`.

  `attrs` keys: `:account_id`, `:region`, `:spec`, `:image_tag`,
  optional `:volume_size_gi` (defaults from the spec catalog).
  """
  def create_server(attrs) do
    attrs = normalize_attrs(attrs)

    with {:ok, region} <- fetch_region(attrs[:region]),
         {:ok, account} <- Accounts.get_account_by_id(attrs[:account_id]),
         attrs = with_defaults(attrs, region),
         {:ok, ref} <- region.provisioner.provision(account, region, server_stub(attrs)) do
      attrs = Map.put(attrs, :provisioner_node_ref, ref)
      insert_server_and_enqueue(attrs, region)
    end
  end

  defp insert_server_and_enqueue(attrs, region) do
    Repo.transaction(fn ->
      with {:ok, server} <- attrs |> Server.create_changeset() |> Repo.insert(),
           {:ok, deployment} <- insert_initial_deployment(server, region, attrs[:image_tag]),
           {:ok, job} <- enqueue_rollout(deployment),
           {:ok, _} <- stamp_job_id(deployment, job.id) do
        server = Repo.preload(server, :deployments)
        broadcast_server(server, :created)
        server
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp insert_initial_deployment(server, region, image_tag) do
    %{
      cluster_id: deployment_cluster_id(region),
      image_tag: image_tag,
      kura_server_id: server.id
    }
    |> Deployment.create_changeset()
    |> Repo.insert()
  end

  defp normalize_attrs(attrs) do
    Map.new(attrs, fn
      {key, value} when is_atom(key) -> {key, value}
      {key, value} -> {String.to_existing_atom(key), value}
    end)
  end

  defp with_defaults(attrs, _region) do
    Map.put_new_lazy(attrs, :volume_size_gi, fn ->
      Specs.default_volume_gi(attrs[:spec] || :medium) || 200
    end)
  end

  defp fetch_region(nil) do
    {:error, %Ecto.Changeset{errors: [region: {"can't be blank", []}]}}
  end

  defp fetch_region(region_id) do
    cond do
      region = Regions.available_region(region_id) ->
        {:ok, region}

      Regions.exists?(region_id) ->
        {:error, %Ecto.Changeset{errors: [region: {"is not available in this environment", []}]}}

      true ->
        {:error, %Ecto.Changeset{errors: [region: {"is not a registered region", []}]}}
    end
  end

  defp server_stub(attrs) do
    struct(Server, Map.take(attrs, [:spec, :volume_size_gi]))
  end

  # The deployment row stored in `kura_deployments` carries `cluster_id`
  # as an audit field — which backing cluster an install or update
  # attempt actually targeted. Filled from the
  # region's provisioner_config so operators see something concrete (e.g.
  # "eu-1") instead of the abstract region ID.
  defp deployment_cluster_id(%Regions{provisioner_config: %{cluster_id: id}}), do: id
  defp deployment_cluster_id(%Regions{id: id}), do: id

  @doc """
  Returns the non-destroyed servers for an account, each with its
  deployment history preloaded newest-first so the /ops UI can link
  straight to the latest log tail.
  """
  def list_servers_for_account(account_id) do
    deployments_query = from(d in Deployment, order_by: [desc: d.inserted_at, desc: d.id])

    Server
    |> where([s], s.account_id == ^account_id and s.status != :destroyed)
    |> order_by([s], asc: s.region, asc: s.spec)
    |> preload(deployments: ^deployments_query)
    |> Repo.all()
  end

  @doc "Fetches a server scoped to the given account."
  def get_server(account_id, server_id) do
    Repo.get_by(Server, id: server_id, account_id: account_id)
  end

  @doc """
  Marks a server as `:active`, mirrors its URL into
  `account_cache_endpoints`, and broadcasts.
  """
  def activate_server(%Server{} = server, image_tag) when is_binary(image_tag) do
    {:ok, account} = Accounts.get_account_by_id(server.account_id)
    url = Provisioner.public_url(account, server)

    Repo.transaction(fn ->
      {:ok, server} =
        server
        |> Server.status_changeset(%{status: :active, url: url, current_image_tag: image_tag})
        |> Repo.update()

      ensure_cache_endpoint(account, url)
      broadcast_server(server, :updated)
      server
    end)
  end

  @doc "Marks a server as `:failed` after an unrecoverable rollout error."
  def fail_server(%Server{} = server) do
    {:ok, server} = server |> Server.status_changeset(%{status: :failed}) |> Repo.update()
    broadcast_server(server, :updated)
    {:ok, server}
  end

  @doc """
  Schedules destruction. Marks the server `:destroying`, removes the
  cache-endpoint mirror immediately so the CLI stops resolving the URL,
  and enqueues the destroy worker.
  """
  def destroy_server(%Server{} = server) do
    Repo.transaction(fn ->
      {:ok, server} =
        server |> Server.status_changeset(%{status: :destroying}) |> Repo.update()

      remove_cache_endpoint(server)
      {:ok, _} = %{server_id: server.id} |> DestroyServerWorker.new() |> Oban.insert()
      broadcast_server(server, :updated)
      server
    end)
  end

  @doc "Marks a server as `:destroyed` after the destroy worker finishes."
  def mark_destroyed(%Server{} = server) do
    {:ok, server} =
      server |> Server.status_changeset(%{status: :destroyed, url: nil}) |> Repo.update()

    broadcast_server(server, :destroyed)
    {:ok, server}
  end

  defp ensure_cache_endpoint(account, url) do
    # Idempotent: a duplicate (account, technology, url) hits the
    # unique constraint and we're done.
    case Accounts.create_account_cache_endpoint(account, %{url: url, technology: :kura}) do
      {:ok, _} -> :ok
      {:error, %Ecto.Changeset{}} -> :ok
    end
  end

  defp remove_cache_endpoint(%Server{url: nil}), do: :ok

  defp remove_cache_endpoint(%Server{account_id: account_id, url: url}) do
    Repo.delete_all(from(e in AccountCacheEndpoint, where: e.account_id == ^account_id and e.url == ^url))
    :ok
  end

  ## Deployments

  @doc """
  Inserts a `Deployment` deployment record and enqueues the rollout
  worker.
  """
  def create_deployment(%Server{} = server, image_tag) when is_binary(image_tag) do
    Repo.transaction(fn ->
      with {:ok, deployment} <- insert_deployment(server, image_tag),
           {:ok, job} <- enqueue_rollout(deployment),
           {:ok, deployment} <- stamp_job_id(deployment, job.id) do
        deployment
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp insert_deployment(%Server{} = server, image_tag) do
    with {:ok, region} <- Regions.fetch(server.region) do
      %{
        cluster_id: deployment_cluster_id(region),
        image_tag: image_tag,
        kura_server_id: server.id
      }
      |> Deployment.create_changeset()
      |> Repo.insert()
    end
  end

  defp enqueue_rollout(%Deployment{id: id}) do
    %{deployment_id: id} |> RolloutWorker.new() |> Oban.insert()
  end

  defp stamp_job_id(deployment, job_id) do
    deployment
    |> Deployment.status_changeset(%{oban_job_id: job_id, status: :pending})
    |> Repo.update()
  end

  @doc "Returns deployment records for the account, newest first."
  def list_deployments_for_account(account_id, limit \\ 50) do
    Deployment
    |> join(:inner, [d], s in assoc(d, :kura_server))
    |> where([_d, s], s.account_id == ^account_id)
    |> order_by([d], desc: d.inserted_at, desc: d.id)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc "Fetches a deployment record, scoped so URLs cannot enumerate."
  def get_deployment(account_id, deployment_id) do
    Deployment
    |> join(:inner, [d], s in assoc(d, :kura_server))
    |> where([d, s], d.id == ^deployment_id and s.account_id == ^account_id)
    |> select([d, _s], d)
    |> Repo.one()
  end

  @doc "Marks a deployment record as running and stamps the start time."
  def mark_running(%Deployment{} = deployment) do
    update_deployment_status(deployment, %{
      status: :running,
      started_at: now_truncated()
    })
  end

  @doc "Marks a deployment record as succeeded."
  def mark_succeeded(%Deployment{} = deployment) do
    update_deployment_status(deployment, %{
      status: :succeeded,
      error_message: nil,
      finished_at: now_truncated()
    })
  end

  @doc "Marks a deployment record as failed."
  def mark_failed(%Deployment{} = deployment, message) when is_binary(message) do
    update_deployment_status(deployment, %{
      status: :failed,
      error_message: message,
      finished_at: now_truncated()
    })
  end

  @doc "Marks a deployment record as cancelled before the provisioner runs."
  def mark_cancelled(%Deployment{} = deployment, message) when is_binary(message) do
    update_deployment_status(deployment, %{
      status: :cancelled,
      error_message: message,
      finished_at: now_truncated()
    })
  end

  defp update_deployment_status(deployment, attrs) do
    deployment |> Deployment.status_changeset(attrs) |> Repo.update()
  end

  defp now_truncated, do: DateTime.truncate(DateTime.utc_now(), :second)

  ## Logs (ClickHouse)

  @doc """
  Appends a batch of `{sequence, stream, line}` log lines for a
  deployment record. Stream is `:stdout` or `:stderr`. Sequences are caller-
  assigned so ordering is stable across ClickHouse parts.
  """
  def append_log_lines(_deployment_id, []), do: {:ok, 0}

  def append_log_lines(deployment_id, lines) when is_list(lines) do
    rows =
      Enum.map(lines, fn {seq, stream, line} ->
        [
          deployment_id: deployment_id,
          sequence: seq,
          stream: Atom.to_string(stream),
          line: line
        ]
      end)

    {count, _} = IngestRepo.insert_all(DeploymentLogLine, rows)
    {:ok, count}
  end

  @doc "Returns log lines for a deployment record, oldest first, capped at `limit`."
  def list_log_lines(deployment_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 1_000)
    after_sequence = Keyword.get(opts, :after_sequence, 0)

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
           "after_sequence" => max(after_sequence, 0),
           "limit" => limit
         }) do
      {:ok, %{rows: rows}} ->
        Enum.map(rows, fn [seq, stream, line, inserted_at] ->
          %{
            sequence: seq,
            stream: parse_stream(stream),
            line: line,
            inserted_at: inserted_at
          }
        end)

      {:error, _reason} ->
        []
    end
  end

  defp parse_stream("stdout"), do: :stdout
  defp parse_stream("stderr"), do: :stderr
  defp parse_stream(other), do: other

  @doc false
  def next_log_sequence(deployment_id) do
    query = """
    SELECT sequence
    FROM kura_deployment_log_lines
    WHERE deployment_id = {deployment_id:UUID}
    ORDER BY sequence DESC
    LIMIT 1
    """

    case IngestRepo.query(query, %{"deployment_id" => deployment_id}) do
      {:ok, %{rows: [[sequence]]}} -> sequence + 1
      _ -> 1
    end
  end

  ## PubSub

  @doc """
  Subscribe the calling process to server lifecycle events for an
  account. Messages arrive as
  `{:kura_server, :created | :updated | :destroyed, %Server{}}`.
  """
  def subscribe_to_account(account_id) do
    PubSub.subscribe(@pubsub, account_topic(account_id))
  end

  defp broadcast_server(%Server{account_id: account_id} = server, event) do
    PubSub.broadcast(@pubsub, account_topic(account_id), {:kura_server, event, server})
  end

  defp account_topic(account_id), do: "kura:account:#{account_id}"

  ## Region catalog (re-exported)

  defdelegate regions, to: Regions, as: :all
  defdelegate region(id), to: Regions, as: :get
  defdelegate specs, to: Specs, as: :all
end
