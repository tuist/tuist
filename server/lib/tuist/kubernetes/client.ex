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

  No watches, no informers, no CRDs. Reconciliation runs as an Oban
  cron at 60 s cadence — well below the substrate's reaction time
  for warm-Pod cycle, simple to operate, no long-lived BEAM
  processes holding API server connections.
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
