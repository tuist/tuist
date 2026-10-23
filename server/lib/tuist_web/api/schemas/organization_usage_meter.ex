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
        description: "The amount beyond the included allowance."
      },
      charge_cents: %Schema{
        type: :integer,
        description:
          "What the billable amount is charged so far, in US cents. Only Pro accounts are charged for it; other plans report 0."
      }
    },
    required: [:used, :included, :billable, :charge_cents]
  })
end
