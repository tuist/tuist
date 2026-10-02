defmodule Atlas.MCP.Tools.GetNudgeAnalyticsStatus do
  @moduledoc """
  Operational read on the state of the nudge analytics pipeline for one
  account: how many of the last 30 daily buckets have landed, when the
  most recent successful bucket was computed, and the last refresh error
  (if any). Used for triage when a signal isn't firing.
  """

  use Atlas.MCP.Tool,
    name: "get_nudge_analytics_status",
    schema: %{
      "type" => "object",
      "properties" => Atlas.MCP.AccountLookup.identifier_schema_properties()
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "account_id" => %{"type" => "string"},
        "buckets_present_last_30_days" => %{"type" => "integer"},
        "latest_ok_bucket_date" => %{"type" => ["string", "null"]},
        "latest_ok_bucket_computed_at" => %{"type" => ["string", "null"]},
        "latest_failed_bucket_date" => %{"type" => ["string", "null"]},
        "latest_refresh_error" => %{"type" => ["string", "null"]},
        "air_status" => %{
          "type" => ["object", "null"],
          "properties" => %{
            "metric" => %{"type" => "string"},
            "period_start" => %{"type" => "string"},
            "distinct_thresholds_delivered" => %{"type" => "integer"},
            "refresh_status" => %{"type" => "string"},
            "refresh_error" => %{"type" => ["string", "null"]},
            "computed_at" => %{"type" => "string"}
          },
          "required" => [
            "metric",
            "period_start",
            "distinct_thresholds_delivered",
            "refresh_status",
            "computed_at"
          ],
          "additionalProperties" => false
        }
      },
      "required" => [
        "account_id",
        "buckets_present_last_30_days",
        "latest_ok_bucket_date",
        "latest_ok_bucket_computed_at",
        "latest_failed_bucket_date",
        "latest_refresh_error",
        "air_status"
      ],
      "additionalProperties" => false
    }

  import Ecto.Query

  alias Atlas.MCP.AccountLookup
  alias Atlas.MCP.Tool
  alias Atlas.Nudges.Analytics.AirStatus
  alias Atlas.Nudges.Analytics.MetricBucket
  alias Atlas.Repo

  @impl EMCP.Tool
  def description do
    "Show the analytics pipeline status for an account so an operator can tell 'we could not measure' apart from 'genuinely quiet.' Reports last 30 days of bucket completeness, the last successful and failed bucket dates, the most recent refresh error, and the current Air status snapshot."
  end

  def execute(_conn, args) do
    with {:ok, account} <- AccountLookup.resolve(args) do
      cutoff = Date.utc_today() |> Date.add(-30)

      buckets =
        Repo.all(
          from b in MetricBucket,
            where: b.account_id == ^account.id and b.bucket_date >= ^cutoff,
            order_by: [desc: b.bucket_date]
        )

      latest_ok = Enum.find(buckets, &(&1.refresh_status == "ok"))
      latest_failed = Enum.find(buckets, &(&1.refresh_status == "failed"))

      {:ok,
       %{
         account_id: account.id,
         buckets_present_last_30_days: Enum.count(buckets, &(&1.refresh_status == "ok")),
         latest_ok_bucket_date: latest_ok && Date.to_iso8601(latest_ok.bucket_date),
         latest_ok_bucket_computed_at: latest_ok && Tool.iso8601(latest_ok.computed_at),
         latest_failed_bucket_date: latest_failed && Date.to_iso8601(latest_failed.bucket_date),
         latest_refresh_error: latest_failed && latest_failed.refresh_error,
         air_status: serialize_air_status(account.id)
       }}
    end
  end

  defp serialize_air_status(account_id) do
    case Repo.one(
           from a in AirStatus,
             where: a.account_id == ^account_id,
             order_by: [desc: a.period_start],
             limit: 1
         ) do
      nil ->
        nil

      %AirStatus{} = status ->
        %{
          metric: status.metric,
          period_start: Date.to_iso8601(status.period_start),
          distinct_thresholds_delivered: status.distinct_thresholds_delivered,
          refresh_status: status.refresh_status,
          refresh_error: status.refresh_error,
          computed_at: Tool.iso8601(status.computed_at)
        }
    end
  end
end
