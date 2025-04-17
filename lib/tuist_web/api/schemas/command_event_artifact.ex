defmodule TuistWeb.API.Schemas.CommandEventArtifact do
  @moduledoc """
  The schema for the command event artifact.
  """

  alias OpenApiSpex.Schema

  require OpenApiSpex

  OpenApiSpex.schema(%{
    title: "CommandEventArtifact",
    description: "It represents an artifact that's associated with a command event (e.g. result bundles)",
    type: :object,
    properties: %{
      type: %Schema{
        description: """
        The command event artifact type. It can be:
        - result_bundle: A result bundle artifact that represents the whole `.xcresult` bundle
        - invocation_record: An invocation record artifact. This is a root bundle object of the result bundle
        - result_bundle_object: A result bundle object. There are many different bundle objects per result bundle.
        """,
        type: :string,
        enum: ["result_bundle", "invocation_record", "result_bundle_object"]
      },
      name: %Schema{
        description: "The name of the file. It's used only for certain types such as result_bundle_object",
        type: :string
      }
    },
    required: [:type]
  })
end
