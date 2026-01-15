defmodule TuistWeb.API.Schemas.TestCaseRead do
  @moduledoc """
  The schema for the test case response.
  """
  alias OpenApiSpex.Schema

  require OpenApiSpex

  OpenApiSpex.schema(%{
    title: "TestCaseRead",
    type: :object,
    description: "Represents a single test case.",
    required: [:id, :name, :module_name, :suite_name, :last_status, :last_duration, :last_ran_at, :url],
    properties: %{
      id: %Schema{type: :string, description: "The unique identifier of the test case"},
      name: %Schema{type: :string, description: "The name of the test case"},
      module_name: %Schema{type: :string, description: "The module name of the test case"},
      suite_name: %Schema{type: :string, description: "The suite name of the test case"},
      last_status: %Schema{type: :string, description: "The last status of the test case"},
      last_duration: %Schema{type: :integer, description: "The duration of the last run in milliseconds"},
      last_ran_at: %Schema{
        type: :integer,
        format: :int64,
        description: "Unix timestamp in seconds since epoch (1970-01-01T00:00:00Z)",
        example: 1_715_606_400
      },
      avg_duration: %Schema{type: :integer, description: "The average duration of the test case in milliseconds"},
      url: %Schema{type: :string, description: "The URL to access the test case"}
    }
  })
end
