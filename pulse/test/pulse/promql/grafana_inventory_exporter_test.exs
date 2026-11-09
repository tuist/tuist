defmodule Pulse.PromQL.GrafanaInventoryExporterTest do
  use Pulse.Test.Case, async: true

  @script Path.expand("../../../scripts/grafana_inventory.exs", __DIR__)
  @dashboards Path.expand("../../../../infra/grafana-dashboards", __DIR__)

  defp export(directory) do
    {output, status} = System.cmd("elixir", [@script, directory], env: [{"ERL_FLAGS", "+S 2:2"}])
    assert status == 0, output
    JSON.decode!(output)
  end

  test "all checked-in v1 and v2 dashboards contribute contracts without misclassifying TraceQL" do
    queries = export(@dashboards)
    sources = @dashboards |> Path.join("*.json") |> Path.wildcard() |> Enum.map(&Path.basename/1) |> Enum.sort()
    assert queries |> Enum.map(& &1["source"]) |> Enum.uniq() |> Enum.sort() == sources
    assert length(sources) == 19
    assert Enum.any?(queries, &(&1["language"] == "sql"))
    assert Enum.any?(queries, &(&1["language"] == "grafana-expression"))
    assert Enum.any?(queries, &(&1["context"] == "variable" and &1["language"] == "logql"))

    traces = Enum.filter(queries, &(&1["source"] == "registry-service.json" and &1["query_type"] == "traceql"))
    assert traces != []
    assert Enum.all?(traces, &(&1["language"] == "traceql" and &1["datasource"] == "tempo"))
    assert Enum.any?(queries, &(&1["instant"] == true and &1["range"] == false and &1["query_type"] == "range"))
    assert export(@dashboards) == queries
  end

  @tag :tmp_dir
  test "v1 inheritance, string/object variables, modes and exclusions are observable", %{tmp_dir: directory} do
    dashboard = %{
      "templating" => %{
        "list" => [
          %{"type" => "datasource", "name" => "ds", "query" => "prometheus"},
          %{"type" => "query", "datasource" => "${ds}", "query" => "label_names()"},
          %{"type" => "query", "datasource" => "$ds", "query" => %{"query" => "label_values(up, job)", "qryType" => 1}},
          %{"type" => "custom", "query" => "not a backend query"}
        ]
      },
      "panels" => [
        %{
          "datasource" => "$ds",
          "targets" => [
            %{"expr" => "up", "instant" => true, "range" => false},
            %{"expr" => "up", "instant" => false, "range" => true},
            %{"expr" => ""}
          ]
        }
      ]
    }

    File.write!(Path.join(directory, "dashboard.json"), JSON.encode!(dashboard))
    queries = export(directory)
    assert length(queries) == 4
    assert Enum.all?(queries, &(&1["language"] == "promql" and &1["datasource"] == "prometheus"))
    assert Enum.count(queries, &(&1["context"] == "variable")) == 2
    assert Enum.count(queries, &(&1["expression"] == "up")) == 2
  end
end
