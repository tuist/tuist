defmodule TuistWeb.API.Schemas.TestCase do
  @moduledoc """
  The schema for the test case response.
  """
  alias OpenApiSpex.Schema

  require OpenApiSpex

  OpenApiSpex.schema(%{
    type: :object,
    description: "The schema for a test case.",
    required: [
      :id,
      :name,
      :module,
      :avg_duration,
      :is_flaky,
      :is_quarantined,
      :url
    ],
    properties: %{
      id: %Schema{
        type: :string,
        format: :uuid,
        description: "ID of the test case"
      },
      name: %Schema{
        type: :string,
        description: "Name of the test case"
      },
      module: %Schema{
        type: :object,
        description: "The module containing the test case",
        required: [:id, :name],
        properties: %{
          id: %Schema{
            type: :string,
            description: "ID of the module"
          },
          name: %Schema{
            type: :string,
            description: "Name of the module"
          }
        }
      },
      suite: %Schema{
        type: :object,
        nullable: true,
        description: "The test suite containing the test case (optional)",
        required: [:id, :name],
        properties: %{
          id: %Schema{
            type: :string,
            description: "ID of the suite"
          },
          name: %Schema{
            type: :string,
            description: "Name of the suite"
          }
        }
      },
      avg_duration: %Schema{
        type: :integer,
        description: "Average duration of recent runs in milliseconds"
      },
      is_flaky: %Schema{
        type: :boolean,
        description: "Whether the test case is marked as flaky"
      },
      is_quarantined: %Schema{
        type: :boolean,
        description: "Whether the test case is quarantined"
      },
      url: %Schema{
        type: :string,
        description: "URL to the test case detail page"
      }
    }
  })
end
