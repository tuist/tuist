defmodule TuistWeb.API.Schemas.RunJobSummary do
  @moduledoc """
  The schema for a run's job summary.
  """

  alias OpenApiSpex.Schema

  require OpenApiSpex

  OpenApiSpex.schema(%{
    title: "RunJobSummary",
    description: "The Tuist Run Report rendered as Markdown for a CI job summary.",
    type: :object,
    properties: %{
      markdown: %Schema{
        type: :string,
        nullable: true,
        description: "The Markdown report, or null when there is nothing to report for the git ref."
      }
    },
    required: [:markdown]
  })
end
