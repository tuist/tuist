defmodule TuistWeb.API.Schemas.AlertRule do
  @moduledoc """
  An alert rule that evaluates a monitor condition and runs trigger/recovery actions.
  """
  alias OpenApiSpex.Schema
  alias TuistWeb.API.Schemas.AlertRuleAction

  require OpenApiSpex

  OpenApiSpex.schema(%{
    title: "AlertRule",
    description: "An alert rule that evaluates a monitor condition and runs trigger/recovery actions.",
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
      trigger_actions: %Schema{type: :array, items: AlertRuleAction},
      recovery_enabled: %Schema{type: :boolean},
      recovery_config: %Schema{type: :object, description: "Recovery parameters (e.g. window)."},
      recovery_actions: %Schema{type: :array, items: AlertRuleAction}
    },
    required: [:id, :name, :enabled, :monitor_type, :trigger_config, :cadence, :trigger_actions]
  })
end
