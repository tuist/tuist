defmodule TuistWeb.API.Schemas.Webhook.Preview do
  @moduledoc """
  The `object` payload shared by every `preview.*` webhook event.

  Mirrors `Tuist.Webhooks.Dispatcher.preview_snapshot/1` — keep both in
  sync when adding fields. Distinct from the API-facing
  `TuistWeb.API.Schemas.Preview`; this one is a flat snapshot scoped to
  what's useful for downstream automations.
  """
  alias OpenApiSpex.Schema

  require OpenApiSpex

  OpenApiSpex.schema(%{
    title: "WebhookPreview",
    description: "Snapshot of the preview that triggered the webhook event.",
    type: :object,
    required: [:id, :project_id, :supported_platforms, :visibility, :inserted_at],
    properties: %{
      id: %Schema{type: :string, description: "Identifier of the preview."},
      display_name: %Schema{
        type: :string,
        nullable: true,
        description: "App display name, when known."
      },
      bundle_identifier: %Schema{
        type: :string,
        nullable: true,
        description: "App bundle identifier, when known."
      },
      version: %Schema{
        type: :string,
        nullable: true,
        description: "App version string, when known."
      },
      project_id: %Schema{type: :integer, description: "Identifier of the project the preview belongs to."},
      supported_platforms: %Schema{
        type: :array,
        items: %Schema{type: :string},
        description:
          "Platforms the preview can run on (e.g. `ios`, `ios_simulator`, `macos`). Empty when not yet detected."
      },
      visibility: %Schema{
        type: :string,
        enum: ["public", "private"],
        description: "Sharing visibility of the preview."
      },
      git_branch: %Schema{
        type: :string,
        nullable: true,
        description: "Git branch the preview was uploaded from."
      },
      git_commit_sha: %Schema{
        type: :string,
        nullable: true,
        description: "Git commit SHA the preview was uploaded from."
      },
      git_ref: %Schema{
        type: :string,
        nullable: true,
        description:
          "Git ref the preview was uploaded from (typically only populated on CI runs from a pull request)."
      },
      inserted_at: %Schema{
        type: :string,
        format: :"date-time",
        description: "ISO-8601 timestamp at which the preview was created."
      }
    }
  })
end
