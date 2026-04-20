defmodule Tuist.Operator do
  @moduledoc """
  The Tuist Runners Kubernetes operator.

  Registers CRDs and controllers with Bonny. Added to the application's
  supervision tree only when `:bonny_enabled` is truthy so local dev and test
  runs don't require a Kubernetes cluster.
  """
  use Bonny.Operator, default_watch_namespace: :all

  alias Bonny.API.CRD

  step(Bonny.Pluggable.Logger, level: :debug)
  step(:delegate_to_controller)

  @impl Bonny.Operator
  def crds do
    [
      CRD.new!(
        group: "tuist.dev",
        scope: :Cluster,
        names: CRD.kind_to_names("OrchardWorkerPool", ["owp"]),
        versions: [Tuist.Operator.V1.OrchardWorkerPool]
      )
    ]
  end

  @impl Bonny.Operator
  def controllers(watching_namespace, _opts) do
    [
      %{
        query: K8s.Client.watch("tuist.dev/v1", "OrchardWorkerPool", namespace: watching_namespace),
        controller: Tuist.Operator.OrchardWorkerPoolController
      }
    ]
  end

  @doc """
  Resolver for Bonny's `get_conn` config.

  Resolution order:

    1. In-cluster service account (auto-mounted at
       `/var/run/secrets/kubernetes.io/serviceaccount`). This is what the
       operator pod uses when deployed to the tuist-runners cluster.
    2. `TUIST_KUBECONFIG_PATH` env var -- used when the operator runs
       outside the cluster (Render staging, local dev against kind).
    3. `~/.kube/config` fallback for local dev convenience.
  """
  def k8s_conn do
    cond do
      File.exists?("/var/run/secrets/kubernetes.io/serviceaccount/token") ->
        K8s.Conn.from_service_account()

      path = System.get_env("TUIST_KUBECONFIG_PATH") ->
        K8s.Conn.from_file(path)

      true ->
        K8s.Conn.from_file(Path.expand("~/.kube/config"))
    end
  end
end
