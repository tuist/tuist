defmodule TuistWeb.API.Schemas.ProjectVCSConnection do
  @moduledoc """
  The repository a project is linked to.
  """

  alias OpenApiSpex.Schema

  require OpenApiSpex

  OpenApiSpex.schema(%{
    type: :object,
    properties: %{
      provider: %Schema{type: :string, enum: ["github", "origin"], description: "The provider hosting the repository."},
      repository_full_handle: %Schema{
        type: :string,
        description: "The repository's full handle, in the format owner/name.",
        example: "tuist/tuist"
      }
    },
    required: [:provider, :repository_full_handle]
  })
end
