defmodule Tuist.Kura do
  @moduledoc """
  Per-account Kura server management.

  Identity is `(account, region)`: an account can light up Kura in as
  many regions as it needs, but only one server per region.

  This context is provisioner-agnostic. The backend resource-allocation
  decisions live behind `Tuist.Kura.Provisioner`; here we ask for an
  opaque `provisioner_node_ref`, persist the server row, and create a
  deployment row for the reconciler to apply.

  Lifecycle transitions broadcast on `"kura:account:<account_id>"` over
  Phoenix.PubSub. When a server reaches `:active` its public URL is
  mirrored into `account_cache_endpoints`; when it's destroyed the row
  is removed. `account_cache_endpoints` is now derived state — operators
  manage Kura through this module, not the endpoints table.
  """

  import Ecto.Query

  alias Phoenix.PubSub
  alias Tuist.Accounts
  alias Tuist.Accounts.Account
  alias Tuist.Accounts.AccountCacheEndpoint
  alias Tuist.Kura.Deployment
  alias Tuist.Kura.Provisioner
  alias Tuist.Kura.Provisioner.KubernetesController
  alias Tuist.Kura.Reconciler
  alias Tuist.Kura.Regions
  alias Tuist.Kura.Server
  alias Tuist.Repo

  @pubsub Tuist.PubSub
  @create_server_keys %{
    "account_id" => :account_id,
    "region" => :region,
    "image_tag" => :image_tag
  }
  @create_server_atom_keys Map.values(@create_server_keys)
  @public_endpoint_timeout 5_000
  @provisioner_node_ref_format ~r/^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$/
  @provisioner_node_ref_max_length 53

  @doc "Reconciles desired Kura server rows with the observed Kubernetes state."
  def reconcile_orphaned_deployments, do: Reconciler.reconcile()

  ## Versions

  @doc """
  Returns the configured Kura runtime version.

  Managed deploys use the runtime image tag declared by deploy
  configuration. GitHub releases can be used as a discovery hint, but the
  rollout source of truth stays in Helm/CI configuration.
  """
  def latest_versions(limit \\ 20)

  def latest_versions(limit) when is_integer(limit) and limit <= 0, do: []

  def latest_versions(limit) when is_integer(limit) do
    runtime_version()
    |> case do
      nil -> []
      version -> [version]
    end
    |> Enum.take(limit)
  end

  def global_cache_endpoint_url(%Account{} = account) do
    with url when is_binary(url) <- global_cache_endpoint_candidate_url(account),
         true <- global_cache_endpoint_active?(account, url) do
      url
    else
      _ -> nil
    end
  end

  def global_cache_endpoint_candidate_url(%Account{name: handle}) do
    if global_cache_endpoint_enabled?(),
      do:
        Enum.find_value(Regions.all(), fn region -> KubernetesController.global_public_url_for_handle(handle, region) end)
  end

  defp global_cache_endpoint_enabled? do
    Tuist.Environment.tuist_hosted?() and not Tuist.Environment.dev?() and not Tuist.Environment.test?()
  end

  def version_label(nil), do: nil

  def version_label("kura@" <> image_tag), do: image_tag

  def version_label(image_tag) when is_binary(image_tag), do: image_tag

  @doc """
  Creates deployments for active Kura servers that are behind the
  latest released Kura runtime image tag.

  Each `(server, image_tag)` pair is scheduled at most once. A failed
  deployment for the configured image is intentionally not retried here;
  operators can inspect and re-trigger it manually, while the next Tuist
  released Kura version will be scheduled normally.
  """
  def schedule_runtime_image_deployments do
    case runtime_image_tag() do
      nil -> {:ok, []}
      image_tag -> schedule_runtime_image_deployments(image_tag)
    end
  end

  defp schedule_runtime_image_deployments(image_tag) do
    with {:ok, version_deployments} <- schedule_version_deployments(image_tag),
         {:ok, global_endpoint_deployments} <- schedule_global_endpoint_deployments(image_tag) do
      {:ok, version_deployments ++ global_endpoint_deployments}
    end
  end

  defp runtime_image_tag do
    case runtime_version() do
      nil -> nil
      %{image_tag: image_tag} -> image_tag
    end
  end

  defp runtime_version do
    case Tuist.Environment.kura_runtime_image_tag() do
      tag when is_binary(tag) ->
        tag = String.trim(tag)

        if tag == "" do
          nil
        else
          %{version: version_label(tag), image_tag: tag, released_at: nil}
        end

      _ ->
        nil
    end
  end

  def schedule_version_deployments(image_tag) when is_binary(image_tag) do
    deployments =
      image_tag
      |> servers_needing_version_query()
      |> Repo.all()
      |> Enum.map(&create_deployment(&1, image_tag))

    case Enum.find(deployments, &match?({:error, _}, &1)) do
      nil -> {:ok, Enum.map(deployments, fn {:ok, deployment} -> deployment end)}
      {:error, reason} -> {:error, reason}
    end
  end

  def schedule_global_endpoint_deployments(image_tag) when is_binary(image_tag) do
    deployments =
      image_tag
      |> servers_needing_global_endpoint_query()
      |> Repo.all()
      |> Enum.filter(&server_needs_global_endpoint?/1)
      |> Enum.map(&create_deployment(&1, image_tag))

    case Enum.find(deployments, &match?({:error, _}, &1)) do
      nil -> {:ok, Enum.map(deployments, fn {:ok, deployment} -> deployment end)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp servers_needing_version_query(image_tag) do
    deployment_exists_query =
      from(d in Deployment,
        where: parent_as(:server).id == d.kura_server_id and d.image_tag == ^image_tag,
        select: 1
      )

    from(s in Server,
      as: :server,
      where: s.status == :active,
      where: s.current_image_tag != ^image_tag,
      where: not exists(deployment_exists_query)
    )
  end

  defp servers_needing_global_endpoint_query(image_tag) do
    open_deployment_exists_query =
      from(d in Deployment,
        where: parent_as(:server).id == d.kura_server_id and d.status in ^[:pending, :running],
        select: 1
      )

    cache_endpoints_query =
      from(e in AccountCacheEndpoint,
        where: e.technology == :kura
      )

    from(s in Server,
      as: :server,
      join: a in assoc(s, :account),
      where: s.region in ^region_ids_with_global_endpoint(),
      where: s.status == :active,
      where: s.current_image_tag == ^image_tag,
      where: not exists(open_deployment_exists_query),
      preload: [account: {a, cache_endpoints: ^cache_endpoints_query}]
    )
  end

  def server_needs_global_endpoint?(%Server{account: %Account{} = account} = server) do
    account_needs_global_endpoint?(account) and region_has_global_endpoint?(server.region)
  end

  def server_global_endpoint_observed?(%Server{} = server) do
    case Provisioner.global_public_url(server) do
      url when is_binary(url) and url != "" -> true
      _ -> false
    end
  end

  defp region_has_global_endpoint?(region_id) do
    case Regions.fetch(region_id) do
      {:ok, %Regions{provisioner_config: config}} -> is_binary(config[:global_public_host_template])
      _ -> false
    end
  end

  defp region_ids_with_global_endpoint do
    Regions.all()
    |> Enum.filter(fn %Regions{provisioner_config: config} -> is_binary(config[:global_public_host_template]) end)
    |> Enum.map(& &1.id)
  end

  ## Servers

  @doc """
  Creates a new Kura server for an account in a region.

  Internally this asks the region's provisioner for an opaque ref,
  inserts a `Server` (status: `:provisioning`) and an initial
  `Deployment` row. The cron reconciler performs the first install.
  Returns `{:ok, server}` (deployment history preloaded) or
  `{:error, reason}`.

  `attrs` keys: `:account_id`, `:region`, `:image_tag`.
  """
  def create_server(attrs) do
    attrs = normalize_attrs(attrs)

    with {:ok, region} <- fetch_region(attrs[:region]),
         {:ok, account} <- Accounts.get_account_by_id(attrs[:account_id]),
         {:ok, ref} <- region.provisioner.provision(account, region, server_stub(attrs)),
         :ok <- validate_provisioner_node_ref(account, ref) do
      attrs = Map.put(attrs, :provisioner_node_ref, ref)
      insert_server(attrs, region)
    end
  end

  defp validate_provisioner_node_ref(account, ref) do
    cond do
      not is_binary(ref) or ref == "" ->
        {:error, account_handle_error(account, "produced an empty Kubernetes resource name for Kura")}

      String.length(ref) > @provisioner_node_ref_max_length ->
        {:error,
         account_handle_error(
           account,
           "is too long for Kura in this region; shorten it so the generated Kubernetes resource name stays under #{@provisioner_node_ref_max_length} characters"
         )}

      not Regex.match?(@provisioner_node_ref_format, ref) ->
        {:error,
         account_handle_error(
           account,
           "must contain only letters, numbers, or hyphens so Kura can create Kubernetes resources"
         )}

      true ->
        :ok
    end
  end

  defp account_handle_error(_account, message) do
    %Server{}
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.add_error(:account_handle, message)
  end

  defp insert_server(attrs, region) do
    case Repo.transaction(fn ->
           with {:ok, server} <- attrs |> Server.create_changeset() |> Repo.insert(),
                {:ok, _deployment} <- insert_initial_deployment(server, region, attrs[:image_tag]) do
             Repo.preload(server, :deployments)
           else
             {:error, reason} -> Repo.rollback(reason)
           end
         end) do
      {:ok, server} ->
        broadcast_server(server, :created)
        {:ok, server}

      {:error, reason} ->
        {:error, reason}
    end
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
    Enum.reduce(attrs, %{}, fn {key, value}, acc ->
      case normalize_create_server_key(key) do
        nil -> acc
        normalized -> Map.put(acc, normalized, value)
      end
    end)
  end

  defp normalize_create_server_key(key) when is_atom(key) do
    if key in @create_server_atom_keys, do: key
  end

  defp normalize_create_server_key(key) when is_binary(key) do
    Map.get(@create_server_keys, key)
  end

  defp normalize_create_server_key(_), do: nil

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

  defp server_stub(_attrs), do: %Server{}

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
  straight to the latest deployment attempt.
  """
  def list_servers_for_account(account_id) do
    deployments_query = from(d in Deployment, order_by: [desc: d.inserted_at, desc: d.id])

    Server
    |> where([s], s.account_id == ^account_id and s.status != :destroyed)
    |> order_by([s], asc: s.region)
    |> preload(deployments: ^deployments_query)
    |> Repo.all()
  end

  @doc "Fetches a server scoped to the given account."
  def get_server(account_id, server_id) do
    Repo.get_by(Server, id: server_id, account_id: account_id)
  end

  @doc """
  Marks a server as `:active`, mirrors its URL into
  `account_cache_endpoints`, and broadcasts. The public endpoint is
  checked first so the CLI doesn't see the URL before external-dns has
  propagated and TLS is serving a valid certificate; the reconciler
  retries on the next tick while the endpoint is not ready.
  """
  def activate_server(%Server{} = server, image_tag) when is_binary(image_tag) do
    with {:ok, account} <- Accounts.get_account_by_id(server.account_id),
         url when is_binary(url) <- Provisioner.public_url(account, server),
         :ok <- ensure_public_endpoint_ready(url),
         {:ok, global_url} <- ready_global_public_url(server),
         {:ok, server} <- activate_server_transaction(server, account, url, global_url, image_tag) do
      broadcast_server(server, :updated)
      {:ok, server}
    else
      {:error, reason} -> {:error, reason}
      reason -> {:error, reason}
    end
  end

  defp ensure_public_endpoint_ready(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host} = uri when scheme in ["http", "https"] and is_binary(host) and host != "" ->
        with :ok <- ensure_public_host_resolves(host) do
          ensure_public_https_up(uri)
        end

      _ ->
        {:error, :public_url_invalid}
    end
  end

  defp ensure_public_host_resolves(host) do
    case :inet.gethostbyname(String.to_charlist(host)) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, {:public_host_not_resolvable, host, reason}}
    end
  end

  defp ensure_public_https_up(%URI{scheme: "https", host: host} = uri) do
    url =
      uri
      |> Map.put(:path, "/up")
      |> Map.put(:query, nil)
      |> Map.put(:fragment, nil)
      |> URI.to_string()

    case Req.get(url,
           receive_timeout: @public_endpoint_timeout,
           connect_options: [timeout: @public_endpoint_timeout],
           retry: false
         ) do
      {:ok, %Req.Response{status: status}} when status in 200..299 ->
        :ok

      {:ok, %Req.Response{status: status}} ->
        {:error, {:public_endpoint_not_ready, host, {:http_status, status}}}

      {:error, reason} ->
        {:error, {:public_endpoint_not_ready, host, reason}}
    end
  end

  defp ensure_public_https_up(_uri), do: :ok

  defp ready_global_public_url(%Server{} = server) do
    case Provisioner.global_public_url(server) do
      url when is_binary(url) and url != "" ->
        with :ok <- ensure_public_endpoint_ready(url) do
          {:ok, url}
        end

      _ ->
        {:ok, nil}
    end
  end

  defp activate_server_transaction(server, account, url, global_url, image_tag) do
    Repo.transaction(fn ->
      case lock_server(server.id, server.account_id) do
        nil ->
          Repo.rollback(:not_found)

        %Server{status: :destroying} ->
          Repo.rollback(:server_destroying)

        %Server{status: :destroyed} ->
          Repo.rollback(:server_destroyed)

        %Server{} = server ->
          with {:ok, server} <-
                 server
                 |> Server.status_changeset(%{status: :active, url: url, current_image_tag: image_tag})
                 |> Repo.update(),
               :ok <- ensure_cache_endpoint(account, url),
               :ok <- ensure_cache_endpoint(account, global_url) do
            server
          else
            {:error, reason} -> Repo.rollback(reason)
          end
      end
    end)
  end

  @doc "Marks a server as `:failed` after an unrecoverable rollout error."
  def fail_server(%Server{} = server) do
    case Repo.transaction(fn ->
           case lock_server(server.id, server.account_id) do
             nil ->
               Repo.rollback(:not_found)

             %Server{status: status} = server when status in [:destroying, :destroyed] ->
               {:ignored, server}

             %Server{} = server ->
               {:ok, server} = server |> Server.status_changeset(%{status: :failed}) |> Repo.update()
               {:updated, server}
           end
         end) do
      {:ok, {:updated, server}} ->
        broadcast_server(server, :updated)
        {:ok, server}

      {:ok, {:ignored, server}} ->
        {:ok, server}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Schedules destruction. Marks the server `:destroying` and removes the
  cache-endpoint mirror immediately so the CLI stops resolving the URL.
  The cron reconciler deletes the backing Kubernetes resource and marks
  the row `:destroyed` once the resource disappears.
  """
  def destroy_server(%Server{} = server) do
    case Repo.transaction(fn ->
           with {:ok, server} <-
                  server |> Server.status_changeset(%{status: :destroying}) |> Repo.update(),
                :ok <- remove_cache_endpoint(server) do
             server
           else
             {:error, reason} -> Repo.rollback(reason)
           end
         end) do
      {:ok, server} ->
        broadcast_server(server, :updated)
        {:ok, server}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Retries a failed first-time deploy in place: flips the `Server` back
  to `:provisioning` and appends a fresh `Deployment` so the
  reconciler picks the retry up on its next tick.

  Only failed servers that never reached `:active` are eligible.
  Retrying a drift failure on a previously-active server would
  trample the cache endpoint that's still serving the old image,
  so the operator has to explicitly destroy those instead.

  The server row, ID, and `provisioner_node_ref` stay the same; the
  prior failed `Deployment` rows stay attached so the failure
  history is visible in /ops alongside the retry.
  """
  def retry_server(%Server{status: :failed, current_image_tag: nil} = server, image_tag) when is_binary(image_tag) do
    with {:ok, region} <- Regions.fetch(server.region) do
      case Repo.transaction(fn ->
             with {:ok, server} <-
                    server |> Server.status_changeset(%{status: :provisioning}) |> Repo.update(),
                  {:ok, _deployment} <- insert_initial_deployment(server, region, image_tag) do
               server
             else
               {:error, reason} -> Repo.rollback(reason)
             end
           end) do
        {:ok, server} ->
          server = Repo.preload(server, :deployments, force: true)
          broadcast_server(server, :updated)
          {:ok, server}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  def retry_server(%Server{}, _image_tag), do: {:error, :not_retryable}

  @doc "Marks a server as `:destroyed` after the reconciler observes teardown."
  def mark_destroyed(%Server{} = server) do
    {:ok, server} =
      server |> Server.status_changeset(%{status: :destroyed, url: nil}) |> Repo.update()

    broadcast_server(server, :destroyed)
    {:ok, server}
  end

  defp ensure_cache_endpoint(_account, nil), do: :ok

  defp ensure_cache_endpoint(account, url) do
    # Kura URLs are deterministic for `(account, region)`, so this
    # derived endpoint row survives destroy/re-create cycles without
    # accumulating stale alternatives for the same server.
    case %AccountCacheEndpoint{}
         |> AccountCacheEndpoint.create_changeset(%{account_id: account.id, url: url, technology: :kura})
         |> Repo.insert(on_conflict: :nothing, conflict_target: [:account_id, :technology, :url]) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp global_cache_endpoint_active?(%Account{cache_endpoints: cache_endpoints}, url) when is_list(cache_endpoints) do
    kura_urls =
      cache_endpoints
      |> Enum.filter(&(&1.technology == :kura))
      |> Enum.map(& &1.url)

    Enum.any?(kura_urls, &(&1 != url)) and url in kura_urls
  end

  defp global_cache_endpoint_active?(%Account{} = account, url) do
    regional_endpoint_exists =
      from(e in AccountCacheEndpoint,
        where: e.account_id == ^account.id and e.technology == :kura and e.url != ^url,
        select: 1
      )

    global_endpoint_exists =
      from(e in AccountCacheEndpoint,
        where: e.account_id == ^account.id and e.technology == :kura and e.url == ^url,
        select: 1
      )

    Repo.exists?(regional_endpoint_exists) and Repo.exists?(global_endpoint_exists)
  end

  defp account_needs_global_endpoint?(%Account{} = account) do
    is_nil(global_cache_endpoint_url(account))
  end

  defp remove_cache_endpoint(%Server{url: nil}), do: :ok

  defp remove_cache_endpoint(%Server{account_id: account_id, url: url}) do
    Repo.delete_all(
      from(e in AccountCacheEndpoint,
        where: e.account_id == ^account_id and e.technology == :kura and e.url == ^url
      )
    )

    :ok
  end

  defp lock_server(id, account_id) do
    Server
    |> where([s], s.id == ^id and s.account_id == ^account_id)
    |> lock("FOR UPDATE")
    |> Repo.one()
  end

  ## Deployments

  @doc """
  Inserts a `Deployment` record for the reconciler to apply.
  """
  def create_deployment(%Server{} = server, image_tag) when is_binary(image_tag) do
    insert_deployment(server, image_tag)
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
    deployment =
      Deployment
      |> join(:inner, [d], s in assoc(d, :kura_server))
      |> where([d, s], d.id == ^deployment_id and s.account_id == ^account_id)
      |> preload([_d, s], kura_server: s)
      |> Repo.one()

    case deployment do
      nil -> {:error, :not_found}
      deployment -> {:ok, deployment}
    end
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
end
