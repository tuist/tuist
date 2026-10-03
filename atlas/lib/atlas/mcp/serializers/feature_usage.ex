defmodule Atlas.MCP.Serializers.FeatureUsage do
  @moduledoc false

  alias Atlas.FeatureUsage.Catalog
  alias Atlas.FeatureUsage.Snapshot

  # `kind` tells the reader how to interpret the counts: for `events` features
  # they are event counts over the window, for `configuration` features
  # `events_last_7d` is the number of enabled rows the account has set up and
  # `events_last_24h` the total including disabled ones (see `Catalog`).
  def snapshot(%Snapshot{} = snapshot) do
    %{
      "feature" => snapshot.feature,
      "label" => Catalog.label(snapshot.feature),
      "kind" => to_string(Catalog.kind(snapshot.feature)),
      "active" => snapshot.active,
      "last_used_at" => datetime(snapshot.last_used_at),
      "events_last_24h" => snapshot.events_last_24h,
      "events_last_7d" => snapshot.events_last_7d,
      "events_prior_7d" => snapshot.events_prior_7d,
      "computed_at" => datetime(snapshot.computed_at)
    }
  end

  def snapshot_schema do
    %{
      "type" => "object",
      "additionalProperties" => false,
      "required" => [
        "feature",
        "label",
        "kind",
        "active",
        "events_last_24h",
        "events_last_7d",
        "events_prior_7d",
        "computed_at"
      ],
      "properties" => %{
        "feature" => %{"type" => "string"},
        "label" => %{"type" => "string"},
        "kind" => %{
          "type" => "string",
          "enum" => ["events", "configuration"],
          "description" =>
            "How the feature is measured. For \"configuration\" features (e.g. automations) the " <>
              "counts are enabled/total rows the account has set up, not events."
        },
        "active" => %{"type" => "boolean"},
        "last_used_at" => %{"type" => ["string", "null"]},
        "events_last_24h" => %{"type" => "integer"},
        "events_last_7d" => %{"type" => "integer"},
        "events_prior_7d" => %{"type" => "integer"},
        "computed_at" => %{"type" => "string"}
      }
    }
  end

  defp datetime(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
  defp datetime(_value), do: nil
end
