defmodule TuistWeb.API.Schemas.OrganizationUsageMeter do
  @moduledoc """
  The usage of one usage-based meter over a billing period.
  """
  alias OpenApiSpex.Schema

  require OpenApiSpex

  OpenApiSpex.schema(%{
    type: :object,
    description:
      "The usage of one usage-based meter over a billing period, in the meter's unit, and what it is charged so far.",
    properties: %{
      used: %Schema{
        type: :integer,
        description:
          "The amount metered so far in the period. For cache meters, traffic served from a Tuist Runners cache region counts at half."
      },
      included: %Schema{
        type: :integer,
        description: "The amount included in every billing period at no cost."
      },
      billable: %Schema{
        type: :integer,
        description: "The amount beyond the included allowance, which is charged."
      },
      charge_cents: %Schema{
        type: :integer,
        description: "The charge for the billable amount so far, in US cents."
      }
    },
    required: [:used, :included, :billable, :charge_cents]
  })
end
