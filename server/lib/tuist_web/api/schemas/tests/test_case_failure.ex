defmodule TuistWeb.API.Schemas.Tests.TestCaseFailure do
  @moduledoc """
  Shared schema for test case failures, used by both test cases and argument variants.
  """
  alias OpenApiSpex.Schema

  require OpenApiSpex

  OpenApiSpex.schema(%{
    title: "TestCaseFailure",
    type: :object,
    description: "A test case failure.",
    properties: %{
      message: %Schema{
        type: :string,
        description: "The failure message."
      },
      path: %Schema{
        type: :string,
        description: "The file path where the failure occurred, relative to the project root."
      },
      line_number: %Schema{
        type: :integer,
        description: "The line number where the failure occurred."
      },
      issue_type: %Schema{
        type: :string,
        description: "The type of issue that occurred.",
        enum: ["error_thrown", "assertion_failure", "issue_recorded"]
      }
    },
    required: [:line_number]
  })
end
