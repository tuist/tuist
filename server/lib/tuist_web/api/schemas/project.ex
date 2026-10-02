defmodule TuistWeb.API.Schemas.Project do
  @moduledoc """
  The schema for the project response.
  """
  alias OpenApiSpex.Schema

  require OpenApiSpex

  OpenApiSpex.schema(%{
    type: :object,
    required: [:id, :full_name, :default_branch, :visibility],
    properties: %{
      id: %Schema{
        type: :number,
        description: "ID of the project"
      },
      full_name: %Schema{
        type: :string,
        description: "The full name of the project (e.g. tuist/tuist)"
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
      token: %Schema{
        type: :string,
        deprecated: true,
        description: "Deprecated. Always returns an empty string."
      },
      visibility: %Schema{
        type: :string,
        description: "The visibility of the project",
        enum: [:private, :public]
      },
      # Not an enum: see the response-enum note in lib/tuist_web/api/AGENTS.md.
      build_system: %Schema{
        type: :string,
        description:
          "The build system used by the project, such as xcode, gradle, bazel, or once. New values can be added without notice, so clients must accept values they don't recognize.",
        example: "xcode"
      }
    }
  })
end
