defmodule TuistWeb.API.Schemas.AutomationAlertAction do
  @moduledoc """
  An action run when an automation alert triggers or recovers.

  The JSON shape is a tagged union keyed on `type`; required sibling fields
  depend on that tag. Only `type` is listed as required at the OpenAPI level
  because JSON Schema doesn't express conditional requirements cleanly; the
  server-side changeset on `Tuist.Automations.Alerts.Alert` enforces the
  per-type contract and returns a 422 with a structured error otherwise.

    * `change_state` — requires `state` (one of `enabled`, `muted`).
    * `add_label` / `remove_label` — requires `label`.
    * `send_slack` — requires `channel` and `message`.
  """
  alias OpenApiSpex.Schema

  require OpenApiSpex

  OpenApiSpex.schema(%{
    title: "AutomationAlertAction",
    description: "An action run when an automation alert triggers or recovers.",
    type: :object,
    properties: %{
      type: %Schema{type: :string, enum: ["change_state", "send_slack", "add_label", "remove_label"]},
      state: %Schema{type: :string, enum: ["enabled", "muted"], description: "Required for change_state actions."},
      label: %Schema{type: :string, description: "Label name. Required for add_label and remove_label actions."},
      channel: %Schema{type: :string, description: "Slack channel ID. Required for send_slack actions."},
      channel_name: %Schema{type: :string, description: "Slack channel name for display."},
      message: %Schema{
        type: :string,
        description: "Message template. Required for send_slack actions. Supports {{variable}} interpolation."
      }
    },
    required: [:type]
  })
end
