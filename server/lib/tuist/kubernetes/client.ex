defmodule Tuist.Kubernetes.Client do
  @moduledoc """
  Thin Kubernetes API client the runner-dispatch flow uses. The
  runners-controller (separate Go process) owns Pod + SA lifecycle;
  the server only needs a handful of read paths plus one Pod
  label-patch:

    * `create_token_review/1` — validate a polling Pod's projected
      SA token (returns the authenticated SA's namespace + name).
    * `get_service_account/2` — resolve the SA → fleet from its
      `tuist.dev/runner-pool` label.
    * `get_runner_pool/2` / `list_runner_pools/1` — fleet discovery.
    * `list_pods/2` — count in-flight Pods per customer (Pods
      labeled `tuist.dev/runner-pool-owner=<owner>`) for
      `max_concurrent` enforcement at dispatch time.
    * `patch_pod/3` — stamp owner labels on a polling Pod the
      moment it claims a queue entry.

  Authenticates with the in-cluster ServiceAccount mount (token at
  `/var/run/secrets/kubernetes.io/serviceaccount/token`, CA at
  `…/ca.crt`, host from `KUBERNETES_SERVICE_HOST`/
  `KUBERNETES_SERVICE_PORT_HTTPS`). Outside the cluster (local
  dev, tests) the functions return `{:error, :not_in_cluster}`
  unless a test override is configured.
  """

  @sa_path "/var/run/secrets/kubernetes.io/serviceaccount"

  @doc """
  POSTs a TokenReview for `token` and returns
  `{:ok, %{namespace: ns, name: sa_name, uid: uid}}` when the
  apiserver authenticates the token AND the principal is a
  ServiceAccount (we reject user / node tokens here so a leaked
  kubeconfig can't impersonate a runner).

  Returns `{:error, :unauthenticated}` when TokenReview rejects
  the token, `{:error, :not_service_account}` when authenticated
  but not an SA, or `{:error, _}` on transport / non-2xx errors.
  """
  def create_token_review(token) when is_binary(token) do
    with {:ok, host, ca, sa_token} <- in_cluster_config() do
      body = %{
        "apiVersion" => "authentication.k8s.io/v1",
        "kind" => "TokenReview",
        "spec" => %{"token" => token}
      }

      req_opts = [
        url: "https://#{host}/apis/authentication.k8s.io/v1/tokenreviews",
        json: body,
        headers: auth_headers(sa_token),
        connect_options: [transport_opts: [cacerts: ca]]
      ]

      case Req.post(req_opts) do
        {:ok, %{status: 201, body: %{"status" => %{"authenticated" => true, "user" => user}}}} ->
          parse_sa_principal(user)

        {:ok, %{status: 201, body: %{"status" => %{"authenticated" => false}}}} ->
          {:error, :unauthenticated}

        {:ok, %{status: status, body: body}} ->
          {:error, {:http, status, body}}

        {:error, reason} ->
          {:error, {:transport, reason}}
      end
    end
  end

  @doc """
  GETs a ServiceAccount by name from `namespace`. The dispatch
  endpoint reads `metadata.labels["tuist.dev/runner-pool"]` to
  resolve which pool the SA-as-caller is authorized for.
  """
  def get_service_account(namespace, name) when is_binary(namespace) and is_binary(name) do
    with {:ok, host, ca, token} <- in_cluster_config() do
      req_opts = [
        url: "https://#{host}/api/v1/namespaces/#{namespace}/serviceaccounts/#{name}",
        headers: auth_headers(token),
        connect_options: [transport_opts: [cacerts: ca]]
      ]

      case Req.get(req_opts) do
        {:ok, %{status: 200, body: sa}} -> {:ok, sa}
        {:ok, %{status: 404}} -> {:error, :not_found}
        {:ok, %{status: status, body: body}} -> {:error, {:http, status, body}}
        {:error, reason} -> {:error, {:transport, reason}}
      end
    end
  end

  @doc """
  GETs a single RunnerPool CR by name. Returns the decoded JSON map
  on success; the caller pulls `spec.owner`, `spec.labels`,
  `spec.runnerGroupID` to drive the JIT mint.
  """
  def get_runner_pool(namespace, name) when is_binary(namespace) and is_binary(name) do
    with {:ok, host, ca, token} <- in_cluster_config() do
      req_opts = [
        url: "https://#{host}/apis/tuist.dev/v1alpha1/namespaces/#{namespace}/runnerpools/#{name}",
        headers: auth_headers(token),
        connect_options: [transport_opts: [cacerts: ca]]
      ]

      case Req.get(req_opts) do
        {:ok, %{status: 200, body: cr}} -> {:ok, cr}
        {:ok, %{status: 404}} -> {:error, :not_found}
        {:ok, %{status: status, body: body}} -> {:error, {:http, status, body}}
        {:error, reason} -> {:error, {:transport, reason}}
      end
    end
  end

  @doc """
  LISTs RunnerPool CRs in `namespace`. The dispatch handler uses
  this to discover the fleet's pool name when writing a Burst CR.
  """
  def list_runner_pools(namespace) when is_binary(namespace) do
    with {:ok, host, ca, token} <- in_cluster_config() do
      req_opts = [
        url: "https://#{host}/apis/tuist.dev/v1alpha1/namespaces/#{namespace}/runnerpools",
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
  LISTs Pods in `namespace` matching `label_selector`. Used by
  `Tuist.Runners.dispatch_for_sa` to count in-flight Pods per
  customer (Pods labeled `tuist.dev/runner-pool-owner=<owner>`)
  before claiming a queue entry, to enforce `max_concurrent`.
  """
  def list_pods(namespace, label_selector) when is_binary(namespace) and is_binary(label_selector) do
    with {:ok, host, ca, token} <- in_cluster_config() do
      req_opts = [
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
  Strategic-merge PATCHes a Pod. The dispatch endpoint uses this
  to stamp owner labels on a polling Pod at the moment it claims
  a queue entry, so subsequent `max_concurrent` counts include
  the Pod immediately.
  """
  def patch_pod(namespace, name, patch) when is_binary(namespace) and is_binary(name) and is_map(patch) do
    with {:ok, host, ca, token} <- in_cluster_config() do
      req_opts = [
        url: "https://#{host}/api/v1/namespaces/#{namespace}/pods/#{name}",
        json: patch,
        headers: [
          {"authorization", "Bearer #{token}"},
          {"accept", "application/json"},
          {"content-type", "application/strategic-merge-patch+json"}
        ],
        connect_options: [transport_opts: [cacerts: ca]]
      ]

      case Req.patch(req_opts) do
        {:ok, %{status: 200, body: pod}} -> {:ok, pod}
        {:ok, %{status: 404}} -> {:error, :not_found}
        {:ok, %{status: status, body: body}} -> {:error, {:http, status, body}}
        {:error, reason} -> {:error, {:transport, reason}}
      end
    end
  end

  defp parse_sa_principal(%{"username" => "system:serviceaccount:" <> rest, "uid" => uid}) do
    case String.split(rest, ":", parts: 2) do
      [namespace, name] when namespace != "" and name != "" ->
        {:ok, %{namespace: namespace, name: name, uid: uid}}

      _ ->
        {:error, :not_service_account}
    end
  end

  defp parse_sa_principal(_), do: {:error, :not_service_account}

  defp auth_headers(token) do
    [
      {"authorization", "Bearer #{token}"},
      {"accept", "application/json"},
      {"content-type", "application/json"}
    ]
  end

  defp in_cluster_config do
    host = System.get_env("KUBERNETES_SERVICE_HOST")

    port =
      System.get_env("KUBERNETES_SERVICE_PORT_HTTPS") ||
        System.get_env("KUBERNETES_SERVICE_PORT") || "443"

    with true <- is_binary(host) and host != "",
         {:ok, token} <- File.read(Path.join(@sa_path, "token")),
         {:ok, ca_pem} <- File.read(Path.join(@sa_path, "ca.crt")) do
      {:ok, "#{host}:#{port}", ca_pem |> :public_key.pem_decode() |> Enum.map(&elem(&1, 1)), String.trim(token)}
    else
      _ -> {:error, :not_in_cluster}
    end
  end
end
