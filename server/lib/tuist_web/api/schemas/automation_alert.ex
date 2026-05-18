defmodule TuistWeb.API.Schemas.AutomationAlert do
  @moduledoc """
  An automation alert — a rule that evaluates a monitor condition and runs trigger/recovery actions.
  """
  alias OpenApiSpex.Schema
  alias TuistWeb.API.Schemas.AutomationAlertAction

  require OpenApiSpex

  OpenApiSpex.schema(%{
    title: "AutomationAlert",
    description: "An automation alert — a rule that evaluates a monitor condition and runs trigger/recovery actions.",
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      name: %Schema{type: :string},
      enabled: %Schema{type: :boolean},
      monitor_type: %Schema{
        type: :string,
        enum: ["flakiness_rate", "flaky_run_count"],
        description: "The monitor type that evaluates the condition."
      },
      trigger_config: %Schema{type: :object, description: "Monitor-specific trigger parameters (e.g. threshold, window)."},
      cadence: %Schema{type: :string, description: "Evaluation cadence (e.g. \"5m\")."},
      trigger_actions: %Schema{type: :array, items: AutomationAlertAction},
      recovery_enabled: %Schema{type: :boolean},
      recovery_config: %Schema{type: :object, description: "Recovery parameters (e.g. window)."},
      recovery_actions: %Schema{type: :array, items: AutomationAlertAction}
    },
    required: [:id, :name, :enabled, :monitor_type, :trigger_config, :cadence, :trigger_actions]
  })

  @doc """
  Serialises a persisted `Tuist.Automations.Alerts.Alert` into the JSON shape
  this schema describes. Kept alongside the schema so the wire contract and
  the serializer move together.
  """
  def from_model(%Tuist.Automations.Alerts.Alert{} = alert) do
    %{
      id: alert.id,
      name: alert.name,
      enabled: alert.enabled,
      monitor_type: alert.monitor_type,
      trigger_config: alert.trigger_config,
      cadence: alert.cadence,
      trigger_actions: alert.trigger_actions,
      recovery_enabled: alert.recovery_enabled,
      recovery_config: alert.recovery_config,
      recovery_actions: alert.recovery_actions
    }
  end
end
