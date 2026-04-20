defmodule Tuist.Operator.V1.OrchardWorkerPool do
  @moduledoc """
  `v1` schema for the `OrchardWorkerPool` custom resource (`tuist.dev/v1`).

  Declarative desired state for a pool of Scaleway bare-metal Macs. Cluster
  operators manage fleet size with standard k8s primitives
  (`kubectl apply -f pool.yaml`, `kubectl scale --replicas=N`). The paired
  controller (`Tuist.Operator.OrchardWorkerPoolController`) reconciles CRs
  against `Tuist.Runners.OrchardWorkerPool` database rows.
  """
  use Bonny.API.Version

  @impl true
  def manifest do
    struct!(
      defaults(),
      storage: true,
      subresources: %{status: %{}},
      additionalPrinterColumns: [
        %{name: "Account", type: "integer", jsonPath: ".spec.accountId"},
        %{name: "Desired", type: "integer", jsonPath: ".spec.desiredSize"},
        %{name: "Current", type: "integer", jsonPath: ".status.currentSize"},
        %{name: "Phase", type: "string", jsonPath: ".status.phase"},
        %{name: "Age", type: "date", jsonPath: ".metadata.creationTimestamp"}
      ],
      schema: %{
        openAPIV3Schema: %{
          type: :object,
          properties: %{
            spec: %{
              type: :object,
              required: ["accountId", "desiredSize", "scalewayZone", "scalewayServerType", "scalewayOs"],
              properties: %{
                accountId: %{type: :integer, description: "Owning Tuist account ID"},
                enabled: %{type: :boolean, default: true},
                desiredSize: %{type: :integer, minimum: 0, maximum: 50},
                scalewayZone: %{type: :string},
                scalewayServerType: %{type: :string},
                scalewayOs: %{type: :string}
              }
            },
            status: %{
              type: :object,
              properties: %{
                phase: %{
                  type: :string,
                  enum: ["Pending", "Reconciling", "Ready", "Disabled", "Failed"]
                },
                currentSize: %{type: :integer},
                lastReconciledAt: %{type: :string, format: "date-time"},
                conditions: %{
                  type: :array,
                  items: %{
                    type: :object,
                    properties: %{
                      type: %{type: :string},
                      status: %{type: :string},
                      reason: %{type: :string},
                      message: %{type: :string},
                      lastTransitionTime: %{type: :string, format: "date-time"}
                    }
                  }
                }
              }
            }
          }
        }
      }
    )
  end
end
