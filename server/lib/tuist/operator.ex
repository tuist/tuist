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
end
