defmodule Pulse.Plans.AlertInventory do
  @moduledoc false
  alias Pulse.Alerting.Canonical
  alias Pulse.Alerting.Graph

  @sources %{
    "grafanacloud-prom" => "prometheus",
    "grafanacloud-logs" => "loki",
    "grafanacloud-usage" => "prometheus",
    "dexgs9hv7rjswd" => "clickhouse",
    "__expr__" => "expression"
  }
  @names %{
    "grafanacloud-prom" => "main metrics",
    "grafanacloud-logs" => "main logs",
    "grafanacloud-usage" => "usage",
    "dexgs9hv7rjswd" => "SQL"
  }

  def validate(snapshot, notifications) do
    rules = snapshot["rules"]

    original =
      Enum.map(rules, fn rule ->
        rule
        |> Map.delete("evaluation_interval_seconds")
        |> Map.update!("data", &Enum.map(&1, fn node -> Map.delete(node, "source_type") end))
      end)

    receivers = Enum.map(notifications["integrations"], & &1["receiver"])

    valid =
      snapshot["schema_version"] == 1 and length(rules) == 115 and
        length(Enum.uniq_by(rules, & &1["uid"])) == 115 and
        Enum.count(rules, &(&1["record"] != nil)) == 4 and
        Enum.count(rules, & &1["isPaused"]) == 2 and
        Enum.count(rules, &(&1["keep_firing_for"] != "0s")) == 13 and
        Canonical.hash(original) == snapshot["provenance"]["original_rules_sha256"] and
        notifications["notification_policy"]["receiver"] in receivers and
        Enum.all?(notifications["notification_policy"]["routes"], &(&1["receiver"] in receivers)) and
        Enum.all?(rules, &rule?(&1, notifications, receivers))

    if valid,
      do: {:ok, rules |> Enum.flat_map(& &1["data"]) |> Enum.frequencies_by(& &1["source_type"])},
      else: {:error, :invalid_inventory}
  rescue
    _ -> {:error, :invalid_inventory}
  end

  defp rule?(rule, notifications, receivers) do
    rule["evaluation_interval_seconds"] in [60, 300, 600] and is_boolean(rule["isPaused"]) and
      is_binary(rule["keep_firing_for"]) and Regex.match?(~r/\A(?:\d+(?:ms|s|m|h|d|w|y))+\z/, rule["keep_firing_for"]) and
      not Map.has_key?(rule, "keepFiringFor") and
      Map.has_key?(notifications["folder_paths"], rule["folderUID"]) and
      (rule["notification_settings"] == nil or rule["notification_settings"]["receiver"] == nil or
         rule["notification_settings"]["receiver"] in receivers) and
      (rule["record"] == nil or rule["record"]["metric"] == rule["title"]) and
      Graph.validate(rule) == :ok and
      Enum.all?(rule["data"], fn node ->
        Map.has_key?(@sources, node["datasourceUid"]) and @sources[node["datasourceUid"]] == node["source_type"]
      end)
  end

  def render(rules) do
    heading = """
    # Grafana rule-by-rule modeling checklist

    Generated from `grafana-rule-inventory.json` by `mix run --no-start plans/alerting/validate_inventory.exs --write-matrix`.
    All 115 UIDs are included. This is a planning inventory, not a claim of implemented compatibility.
    Every row still requires importer round-trip, source binding, numerical/label/error fixtures,
    routing fixtures and shadow comparison before its migration status can become approved.
    Source query definitions and annotation templates remain in the JSON snapshot.

    `main metrics` and `main logs` identify observed Grafana sources, NOT confirmed Pulse-resident inputs.
    Every selector producer/residency closure remains a migration blocker until verified; recording consumers must move with their inputs.
    `synthetic` identifies externally produced probe/threshold/log inputs and is not implicitly Alloy telemetry.
    `usage` requires Grafana's external usage metrics; `SQL` requires an existing external ClickHouse source.
    Mixed-source rules must remain mixed-source expression graphs. `policy` means notification-tree routing;
    `record` means no alert notification. Blank no-data/error settings belong to recording entries, not default alert policies.

    | UID | Rule | Observed sources (residency unverified) | Expression nodes | Cadence / for / keep-firing | Paused | No-data / error | Receiver |
    | --- | --- | --- | --- | --- | --- | --- | --- |
    """

    rows =
      rules
      |> Enum.sort_by(&{&1["folderUID"], &1["ruleGroup"], &1["title"]})
      |> Enum.map(fn rule ->
        sources =
          rule["data"]
          |> Enum.reject(&(&1["source_type"] == "expression"))
          |> Enum.map(&@names[&1["datasourceUid"]])
          |> Enum.uniq()
          |> Enum.sort()

        sources =
          if rule["folderUID"] == "grafana-synthetic-monitoring-app",
            do: Enum.map(sources, &("synthetic " <> &1)),
            else: sources

        exprs =
          rule["data"]
          |> Enum.filter(&(&1["source_type"] == "expression"))
          |> Enum.map(& &1["model"]["type"])
          |> Enum.uniq()
          |> Enum.sort()

        receiver = if rule["record"], do: "record", else: (rule["notification_settings"] || %{})["receiver"] || "policy"

        row = [
          rule["uid"],
          rule["title"],
          Enum.join(sources, ", "),
          if(exprs == [], do: "source condition", else: Enum.join(exprs, ", ")),
          "#{rule["evaluation_interval_seconds"]}s / #{rule["for"]} / #{rule["keep_firing_for"]}",
          if(rule["isPaused"], do: "yes", else: "no"),
          "#{blank(rule["noDataState"])} / #{blank(rule["execErrState"])}",
          receiver
        ]

        "| " <> Enum.map_join(row, " | ", &cell/1) <> " |\n"
      end)

    IO.iodata_to_binary([heading, rows])
  end

  defp blank(value) when value in [nil, ""], do: "-"
  defp blank(value), do: value
  defp cell(value), do: value |> to_string() |> String.replace("|", "\\|") |> String.replace("\n", " ")
end
