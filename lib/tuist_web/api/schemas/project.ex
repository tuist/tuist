defmodule TuistWeb.API.Schemas.Project do
  @moduledoc """
  The schema for the project response.
  """
  alias OpenApiSpex.Schema

  require OpenApiSpex

  OpenApiSpex.schema(%{
    type: :object,
    required: [:id, :full_name, :token, :default_branch, :visibility],
    properties: %{
      id: %Schema{
        type: :number,
        description: "ID of the project"
      },
      full_name: %Schema{
        type: :string,
        description: "The full name of the project (e.g. tuist/tuist)"
      },
      token: %Schema{
        type: :string,
        description: "The token that should be used to authenticate the project. For CI only.",
        deprecated: true
      },
      default_branch: %Schema{
        type: :string,
        description: "The default branch of the project.",
        example: "main"
      },
      repository_url: %Schema{
        type: :string,
        description:
          "The URL of the connected git repository, such as https://github.com/tuist/tuist or https://github.com/tuist/tuist.git"
      },
      visibility: %Schema{
        type: :string,
        description: "The visibility of the project",
        enum: [:private, :public]
      }
    }
  })
end
