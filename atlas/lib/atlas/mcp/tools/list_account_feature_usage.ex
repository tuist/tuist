defmodule Atlas.MCP.Tools.ListAccountFeatureUsage do
  @moduledoc """
  Lists recent "stopped using a feature" transitions across accounts.
  """

  use Atlas.MCP.Tool,
    name: "list_account_feature_usage",
    schema: %{
      "type" => "object",
      "properties" => %{
        "feature" => %{
          "type" => "string",
          "description" => ~s{Optional feature slug to filter by (e.g. "cache", "test_analytics").}
        },
        "since_days" => %{
          "type" => "integer",
          "minimum" => 1,
          "description" => "Only include transitions computed within the last N days."
        },
        "limit" => %{
          "type" => "integer",
          "minimum" => 1,
          "maximum" => 200,
          "description" => "Maximum transitions to return (default 50)."
        }
      }
    },
    output_schema: %{
      "type" => "object",
      "additionalProperties" => false,
      "required" => ["stopped_using", "count"],
      "properties" => %{
        "count" => %{"type" => "integer"},
        "stopped_using" => %{
          "type" => "array",
          "items" => %{
            "type" => "object",
            "additionalProperties" => false,
            "required" => ["account_id", "account_name", "feature"],
            "properties" => %{
              "account_id" => %{"type" => "string"},
              "account_name" => %{"type" => ["string", "null"]},
              "feature" => Atlas.MCP.Serializers.FeatureUsage.snapshot_schema()
            }
          }
        }
      }
    }

  alias Atlas.Accounts.Account
  alias Atlas.FeatureUsage
  alias Atlas.MCP.Serializers.FeatureUsage, as: FeatureUsageSerializer

  @impl EMCP.Tool
  def description do
    "List accounts that recently stopped using a Tuist feature (active in the prior 7-day window, " <>
      "zero usage in the last 7 days). Optionally filter by feature slug. Use this to see churn " <>
      "signals across the customer base."
  end

  def execute(_conn, args) do
    stops = FeatureUsage.list_recent_stops(opts(args))

    entries =
      Enum.map(stops, fn snapshot ->
        %{
          "account_id" => snapshot.account_id,
          "account_name" => account_name(snapshot.account),
          "feature" => FeatureUsageSerializer.snapshot(snapshot)
        }
      end)

    {:ok, %{"stopped_using" => entries, "count" => length(entries)}}
  end

  defp opts(args) do
    []
    |> maybe(:feature, args["feature"])
    |> maybe(:limit, args["limit"])
    |> maybe(:since, since(args["since_days"]))
  end

  defp maybe(opts, _key, nil), do: opts
  defp maybe(opts, key, value), do: Keyword.put(opts, key, value)

  defp since(days) when is_integer(days) and days > 0, do: DateTime.add(DateTime.utc_now(), -days, :day)
  defp since(_days), do: nil

  defp account_name(%Account{name: name}), do: name
  defp account_name(_account), do: nil
end
