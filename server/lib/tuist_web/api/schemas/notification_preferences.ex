defmodule TuistWeb.API.Schemas.NotificationPreferences do
  @moduledoc """
  The signed-in user's choices for one notification kind, shared by every
  notification preference response so clients decode a single type.
  """

  alias OpenApiSpex.Schema

  require OpenApiSpex

  OpenApiSpex.schema(%{
    title: "NotificationPreferences",
    description:
      "The signed-in user's own choices for one notification kind, per account (their personal account and organizations) with project overrides. The choices apply to every delivery channel.",
    type: :object,
    properties: %{
      kind: %Schema{type: :string},
      accounts: %Schema{
        type: :array,
        items: %Schema{
          title: "NotificationPreferencesAccount",
          type: :object,
          properties: %{
            handle: %Schema{type: :string, description: "The account handle."},
            enabled: %Schema{
              type: :boolean,
              description: "The user's choice for the account's projects, including future ones."
            },
            projects: %Schema{
              type: :array,
              items: %Schema{
                title: "NotificationPreferencesProject",
                type: :object,
                properties: %{
                  handle: %Schema{type: :string, description: "The project handle, without the account."},
                  # An open string rather than an enum, so a value added later
                  # does not stop older apps from decoding the whole response.
                  setting: %Schema{
                    type: :string,
                    description:
                      "`default` follows the account; `on` and `off` override it. Treat other values as `default`; `enabled` is always the effective choice."
                  },
                  enabled: %Schema{type: :boolean, description: "Whether the user is notified about this project."}
                },
                required: [:handle, :setting, :enabled]
              }
            }
          },
          required: [:handle, :enabled, :projects]
        }
      }
    },
    required: [:kind, :accounts]
  })
end
