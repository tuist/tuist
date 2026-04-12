defmodule TuistWeb.API.Schemas.Tests.TestCaseRepetition do
  @moduledoc """
  Shared schema for test case repetitions, used by both test cases and argument variants.
  """
  alias OpenApiSpex.Schema

  require OpenApiSpex

  OpenApiSpex.schema(%{
    title: "TestCaseRepetition",
    type: :object,
    description: "A test case repetition attempt.",
    properties: %{
      repetition_number: %Schema{
        type: :integer,
        description: "The repetition attempt number (1 = First Run, 2 = Retry 1, etc.)"
      },
      name: %Schema{
        type: :string,
        description: "The name of the repetition (e.g., 'First Run', 'Retry 1')."
      },
      status: %Schema{
        type: :string,
        description: "The status of this repetition attempt.",
        enum: ["success", "failure"]
      },
      duration: %Schema{
        type: :integer,
        description: "The duration of this repetition in milliseconds."
      }
    },
    required: [:repetition_number, :name, :status]
  })
end
