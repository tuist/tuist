defmodule Tuist.Kubernetes.Client do
  @moduledoc """
  Thin Kubernetes API client used by `Tuist.Runners` to materialize
  warm runner Pods on the Mac mini fleet.

  Authenticates with the in-cluster ServiceAccount mount (token at
  `/var/run/secrets/kubernetes.io/serviceaccount/token`, CA at
  `…/ca.crt`, host from `KUBERNETES_SERVICE_HOST` /
  `KUBERNETES_SERVICE_PORT_HTTPS`). Outside the cluster (local dev,
  tests) the functions return `{:error, :not_in_cluster}` unless a
  test override is configured.

  Doesn't share `Tuist.Finch` because Req rejects combining a
  custom `finch:` pool with `connect_options:` (the pool has its
  own connection settings). The K8s API server uses the cluster
  CA bundle from `/var/run/secrets/.../ca.crt`, which we inject
  via `connect_options.transport_opts.cacerts`. Volume of K8s
  API calls is tiny (per-60s reconcile), so a separate connection
  pool is acceptable.

  Surface intentionally minimal — only the verbs the runners pool
  reconciler needs:

    - `list_pods/2` (label selector, namespace) → counts warm Pods
    - `create_pod/2` (manifest, namespace) → materializes a Pod
    - `list_nodes/1` (label selector) → fleet roster
    - `stream_watch_pods/3` (namespace, selector, callback) →
      long-lived watch on Pod events, drives the reconciler's
      event-driven trigger so warm-pool refills happen the
      moment a Pod terminates instead of on a cron tick

  The reconciler runs from `Tuist.Runners.Watcher` — a GenServer
  that opens a watch on Pod events, calls the reconciler on each
  terminal-state transition, and reconnects with backoff on
  stream end. No periodic polling.
  """

  @sa_path "/var/run/secrets/kubernetes.io/serviceaccount"

  @doc """
  Returns `{:ok, pods}` (list of decoded items from `/api/v1/pods`)
  matching `label_selector` in `namespace`. Returns `{:error, _}`
  on transport error, non-2xx status, or missing in-cluster
  credentials.
  """
  def list_pods(namespace, label_selector) when is_binary(namespace) and is_binary(label_selector) do
    with {:ok, host, ca, token} <- in_cluster_config() do
      req_opts =
        [
          url: "https://#{host}/api/v1/namespaces/#{namespace}/pods",
          params: [{"labelSelector", label_selector}],
          headers: auth_headers(token),
          connect_options: [transport_opts: [cacerts: ca]]
        ]

      case Req.get(req_opts) do
        {:ok, %{status: 200, body: %{"items" => items}}} -> {:ok, items}
        {:ok, %{status: status, body: body}} -> {:error, {:http, status, body}}
        {:error, reason} -> {:error, {:transport, reason}}
      end
    end
  end

  @doc """
  Creates a Pod from a fully-formed manifest map. The caller is
  responsible for shaping the manifest — `Tuist.Runners.PodSpec`
  builds the canonical runner Pod shape.

  Returns `{:ok, pod}` (the API server's view of the newly created
  Pod, with status fields, resourceVersion, etc.) or `{:error, _}`.
  """
  def create_pod(namespace, manifest) when is_binary(namespace) and is_map(manifest) do
    with {:ok, host, ca, token} <- in_cluster_config() do
      req_opts =
        [
          url: "https://#{host}/api/v1/namespaces/#{namespace}/pods",
          json: manifest,
          headers: auth_headers(token),
          connect_options: [transport_opts: [cacerts: ca]]
        ]

      case Req.post(req_opts) do
        {:ok, %{status: 201, body: pod}} -> {:ok, pod}
        {:ok, %{status: status, body: body}} -> {:error, {:http, status, body}}
        {:error, reason} -> {:error, {:transport, reason}}
      end
    end
  end

  @doc """
  Returns `{:ok, nodes}` matching `label_selector`. Cluster-scoped
  resource — the server's ServiceAccount carries a ClusterRole grant
  for `nodes: get,list` (templates/runners-namespace.yaml).
  """
  def list_nodes(label_selector) when is_binary(label_selector) do
    with {:ok, host, ca, token} <- in_cluster_config() do
      req_opts =
        [
          url: "https://#{host}/api/v1/nodes",
          params: [{"labelSelector", label_selector}],
          headers: auth_headers(token),
          connect_options: [transport_opts: [cacerts: ca]]
        ]

      case Req.get(req_opts) do
        {:ok, %{status: 200, body: %{"items" => items}}} -> {:ok, items}
        {:ok, %{status: status, body: body}} -> {:error, {:http, status, body}}
        {:error, reason} -> {:error, {:transport, reason}}
      end
    end
  end

  @doc """
  Opens a long-lived `watch=true` request against the Pod
  collection in `namespace` filtered by `label_selector`, parses
  the JSON-Lines event stream, and invokes `callback` for every
  WatchEvent with `{type, object}`.

  Returns `:ok` when the upstream stream closes cleanly,
  `{:error, reason}` on transport / non-2xx status / invalid
  credentials. The caller (typically `Tuist.Runners.Watcher`)
  handles reconnection with backoff.

  `resource_version` is optional. When passed, the server replays
  events since that revision (useful if the caller persists the
  cursor across reconnects). When omitted, the server starts
  from the current state. We use `omit` and run a fresh LIST on
  every reconnect — simpler than RV bookkeeping, only slightly
  more expensive at reconnect time, and avoids the
  `410 Gone` retry path for stale RVs.

  The HTTP request has no client-side timeout: K8s API servers
  send a TCP FIN at their own idle limit (~5–10 min) and the
  watcher reconnects from there.
  """
  def stream_watch_pods(namespace, label_selector, callback)
      when is_binary(namespace) and is_binary(label_selector) and is_function(callback, 1) do
    with {:ok, host, ca, token} <- in_cluster_config() do
      req_opts =
        [
          url:
            "https://#{host}/api/v1/namespaces/#{namespace}/pods?watch=true&allowWatchBookmarks=true&labelSelector=" <>
              URI.encode_www_form(label_selector),
          headers: auth_headers(token),
          connect_options: [transport_opts: [cacerts: ca]],
          # Watch streams idle indefinitely between events; the
          # API server sends a TCP FIN at its own idle limit
          # (~5–10 min) and the watcher reconnects from there.
          # Disable Req's receive timeout so a quiet stream
          # isn't torn down by the client.
          receive_timeout: :infinity,
          # Buffer raw bytes line-by-line — the K8s watch
          # protocol is JSON-Lines (one JSON object per line)
          # and a TCP frame can split mid-event. The `into`
          # callback re-assembles full lines from chunks and
          # emits each as a decoded map through the user's
          # callback; partial trailing data stays in the
          # buffer until the next chunk arrives.
          into: fn {:data, chunk}, {req, resp} ->
            buffer = Map.get(resp.private, :tuist_buffer, "") <> chunk
            {events, leftover} = split_lines(buffer)
            Enum.each(events, fn line -> dispatch_event(line, callback) end)
            {:cont, {req, %{resp | private: Map.put(resp.private, :tuist_buffer, leftover)}}}
          end
        ]

      case Req.get(req_opts) do
        {:ok, %{status: 200}} -> :ok
        {:ok, %{status: status, body: body}} -> {:error, {:http, status, body}}
        {:error, reason} -> {:error, {:transport, reason}}
      end
    end
  end

  defp split_lines(data) do
    case String.split(data, "\n", trim: false) do
      [single] -> {[], single}
      lines -> {Enum.drop(lines, -1), List.last(lines)}
    end
  end

  defp dispatch_event("", _callback), do: :ok

  defp dispatch_event(line, callback) do
    case Jason.decode(line) do
      {:ok, %{"type" => _type, "object" => _object} = event} -> callback.(event)
      _ -> :ok
    end
  end

  defp auth_headers(token) do
    [
      {"authorization", "Bearer #{token}"},
      {"accept", "application/json"},
      {"content-type", "application/json"}
    ]
  end

  # Resolves the API server host:port + CA bundle + bearer token
  # from the standard in-cluster ServiceAccount mount. Returns
  # `{:error, :not_in_cluster}` outside the cluster so callers
  # surface a clean error instead of a misleading transport
  # failure.
  defp in_cluster_config do
    host = System.get_env("KUBERNETES_SERVICE_HOST")
    port = System.get_env("KUBERNETES_SERVICE_PORT_HTTPS") || System.get_env("KUBERNETES_SERVICE_PORT") || "443"

    with true <- is_binary(host) and host != "",
         {:ok, token} <- File.read(Path.join(@sa_path, "token")),
         {:ok, ca_pem} <- File.read(Path.join(@sa_path, "ca.crt")) do
      {:ok, "#{host}:#{port}", ca_pem |> :public_key.pem_decode() |> Enum.map(&elem(&1, 1)), String.trim(token)}
    else
      _ -> {:error, :not_in_cluster}
    end
  end
end
