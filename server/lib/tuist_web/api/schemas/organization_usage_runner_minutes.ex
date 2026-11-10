defmodule TuistWeb.API.Schemas.OrganizationUsageRunnerMinutes do
  @moduledoc """
  The Tuist Runners usage over a billing period.
  """
  alias OpenApiSpex.Schema

  require OpenApiSpex

  OpenApiSpex.schema(%{
    type: :object,
    description: "The Tuist Runners usage over a billing period and what it is charged so far.",
    properties: %{
      used: %Schema{
        type: :integer,
        description: "The whole runner minutes used so far in the period, across every platform."
      },
      included: %Schema{
        type: :integer,
        description: "The runner minutes included in every billing period at no cost."
      },
      charge_cents: %Schema{
        type: :integer,
        description:
          "The charge so far for the runner usage beyond the included minutes, in US cents. Usage covered by a runner trial and platforms without a rate are not charged."
      }
    },
    required: [:used, :included, :charge_cents]
  })
end
