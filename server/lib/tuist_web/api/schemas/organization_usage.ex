defmodule TuistWeb.API.Schemas.OrganizationUsage do
  @moduledoc """
  A schema for the usage of an organization.
  """
  alias OpenApiSpex.Schema
  alias TuistWeb.API.Schemas.OrganizationUsageMeter
  alias TuistWeb.API.Schemas.OrganizationUsageRunnerMinutes

  require OpenApiSpex

  OpenApiSpex.schema(%{
    type: :object,
    description:
      "The usage of an organization over its current billing period. `cache_egress` is in bytes, `cache_requests` in requests, and `passing_test_cases` in test cases; test cases run on Tuist Runners are not counted. Charges are in US cents.",
    properties: %{
      current_month_remote_cache_hits: %Schema{
        type: :number,
        deprecated: true,
        description: "Deprecated. No longer computed and always 0."
      },
      period: %Schema{
        type: :object,
        description:
          "The current billing period: the subscription's billing cycle, or the calendar month for an organization without a subscription.",
        properties: %{
          start: %Schema{type: :string, format: :"date-time", description: "The start of the period, inclusive."},
          end: %Schema{type: :string, format: :"date-time", description: "The end of the period, exclusive."}
        },
        required: [:start, :end]
      },
      cache_egress: OrganizationUsageMeter,
      cache_requests: OrganizationUsageMeter,
      passing_test_cases: OrganizationUsageMeter,
      runner_minutes: OrganizationUsageRunnerMinutes,
      estimated_charge_cents: %Schema{
        type: :integer,
        description:
          "The sum of the cache, test case, and runner charges so far in the period, in US cents, before any prepaid credit."
      }
    },
    required: [
      :current_month_remote_cache_hits,
      :period,
      :cache_egress,
      :cache_requests,
      :passing_test_cases,
      :runner_minutes,
      :estimated_charge_cents
    ]
  })
end
