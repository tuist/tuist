defmodule TuistWeb.API.Schemas.Preview do
  @moduledoc """
  The schema for the Tuist Preview response.
  """
  alias OpenApiSpex.Schema
  alias TuistWeb.API.Schemas.Account

  require OpenApiSpex

  OpenApiSpex.schema(%{
    type: :object,
    required: [
      :id,
      :url,
      :qr_code_url,
      :icon_url,
      :builds,
      :supported_platforms,
      :inserted_at,
      :created_from_ci,
      :device_url
    ],
    properties: %{
      id: %Schema{
        type: :string,
        description: "Unique identifier of the preview."
      },
      url: %Schema{type: :string, description: "The URL to download the preview"},
      device_url: %Schema{type: :string, description: "The URL to download the preview on a device"},
      qr_code_url: %Schema{
        type: :string,
        description: "The URL for the QR code image to dowload the preview"
      },
      icon_url: %Schema{
        type: :string,
        description: "The URL for the icon image of the preview"
      },
      version: %Schema{
        type: :string,
        description: "The app version of the preview"
      },
      bundle_identifier: %Schema{
        type: :string,
        description: "The bundle identifier of the preview"
      },
      display_name: %Schema{
        type: :string,
        description: "The display name of the preview"
      },
      git_commit_sha: %Schema{
        type: :string,
        description: "The git commit SHA associated with the preview"
      },
      git_branch: %Schema{
        type: :string,
        description: "The git branch associated with the preview"
      },
      track: %Schema{
        type: :string,
        description: "The track for the preview (e.g., 'beta', 'nightly')"
      },
      builds: %Schema{
        type: :array,
        items: TuistWeb.API.Schemas.AppBuild
      },
      supported_platforms: %Schema{
        type: :array,
        items: TuistWeb.API.Schemas.PreviewSupportedPlatform
      },
      inserted_at: %Schema{
        type: :string,
        format: :date_time,
        description: "The date and time when the preview was inserted"
      },
      created_by: Account,
      created_from_ci: %Schema{
        type: :boolean,
        description: "Whether the preview was created from CI"
      }
    }
  })
end
