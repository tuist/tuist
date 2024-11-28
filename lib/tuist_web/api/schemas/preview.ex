defmodule TuistWeb.API.Schemas.Preview do
  @moduledoc """
  The schema for the Tuist Preview response.
  """
  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    type: :object,
    required: [:id, :url, :qr_code_url, :icon_url],
    properties: %{
      id: %Schema{
        type: :string,
        description: "Unique identifier of the preview."
      },
      url: %Schema{type: :string, description: "The URL to download the preview"},
      qr_code_url: %Schema{
        type: :string,
        description: "The URL for the QR code image to dowload the preview"
      },
      icon_url: %Schema{
        type: :string,
        description: "The URL for the icon image of the preview"
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
      }
    }
  })
end
