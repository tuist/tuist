defmodule Tuist.Kubernetes.Client do
  @moduledoc """
  Thin Kubernetes API client used by the runner-dispatch flow.

  The runners-controller (separate Go process) owns Pod + SA
  materialization end-to-end; the server only needs three K8s
  verbs to participate:

    1. `create_token_review/1` — validate a Pod's projected
       ServiceAccount token from the dispatch endpoint, recovering
       the SA's namespace + name without trusting the request
       body.
    2. `get_service_account/2` — read the SA's labels (most
       importantly `tuist.dev/runner-pool`) so the dispatch
       endpoint can resolve which pool the caller is authorized
       for. The SA's labels are the authentic mapping; the Pod
       can't lie about them because TokenReview tied the request
       to the SA.
    3. `create_runner_assignment/2` — when GitHub fires
       `workflow_job: queued` and the matched pool's pre-bound
       runners are saturated, the webhook handler writes a
       RunnerAssignment CR (`trigger: Burst`) and the controller
       picks it up to materialize a fresh Pod.

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
  LISTs RunnerPool CRs in `namespace`. The webhook handler folds
  the result into the `(owner, labels) -> pool` matcher so a queued
  workflow_job binds to the same pool the controller already
  reconciles.
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
  LISTs RunnerAssignment CRs in `namespace`. Used by the dispatch
  endpoint when a SharedWarm Pod polls — the server scans for
  unclaimed Burst CRs and atomically claims one on the Pod's
  behalf.
  """
  def list_runner_assignments(namespace) when is_binary(namespace) do
    with {:ok, host, ca, token} <- in_cluster_config() do
      req_opts = [
        url: "https://#{host}/apis/tuist.dev/v1alpha1/namespaces/#{namespace}/runnerassignments",
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
  PUTs (replaces) a RunnerAssignment CR. Carries the apiserver's
  optimistic-concurrency contract: when `metadata.resourceVersion`
  in `manifest` doesn't match the apiserver's current rv, the
  request returns 409 Conflict. The dispatch endpoint relies on
  this to atomically claim a Burst on behalf of a SharedWarm
  Pod — two warm Pods racing for the same Burst will both LIST,
  one will succeed at Update, the other will see 409 and pick
  a different Burst.
  """
  def update_runner_assignment(namespace, name, manifest)
      when is_binary(namespace) and is_binary(name) and is_map(manifest) do
    with {:ok, host, ca, token} <- in_cluster_config() do
      req_opts = [
        url: "https://#{host}/apis/tuist.dev/v1alpha1/namespaces/#{namespace}/runnerassignments/#{name}",
        json: manifest,
        headers: auth_headers(token),
        connect_options: [transport_opts: [cacerts: ca]]
      ]

      case Req.put(req_opts) do
        {:ok, %{status: 200, body: cr}} -> {:ok, cr}
        {:ok, %{status: 409}} -> {:error, :conflict}
        {:ok, %{status: 404}} -> {:error, :not_found}
        {:ok, %{status: status, body: body}} -> {:error, {:http, status, body}}
        {:error, reason} -> {:error, {:transport, reason}}
      end
    end
  end

  @doc """
  POSTs a RunnerAssignment CR into `namespace` from a fully-shaped
  manifest map. Used by the webhook handler to ask the controller
  to materialize an on-demand Burst Pod.
  """
  def create_runner_assignment(namespace, manifest) when is_binary(namespace) and is_map(manifest) do
    with {:ok, host, ca, token} <- in_cluster_config() do
      req_opts = [
        url: "https://#{host}/apis/tuist.dev/v1alpha1/namespaces/#{namespace}/runnerassignments",
        json: manifest,
        headers: auth_headers(token),
        connect_options: [transport_opts: [cacerts: ca]]
      ]

      case Req.post(req_opts) do
        {:ok, %{status: status, body: cr}} when status in [200, 201] -> {:ok, cr}
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
