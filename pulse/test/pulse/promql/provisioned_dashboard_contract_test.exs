defmodule Pulse.PromQL.ProvisionedDashboardContractTest do
  use Pulse.Test.Case, async: true

  alias Pulse.PromQL.Parser

  test "every raw provisioned metrics contract parses after dashboard-variable substitution" do
    queries =
      "../../fixtures/grafana/dashboard-queries.json"
      |> Path.expand(__DIR__)
      |> File.read!()
      |> JSON.decode!()

    {non_metrics, metrics} =
      Enum.split_with(queries, &(&1["datasource"] in ["$logs_datasource", "$traces_datasource"]))

    assert length(metrics) == 301
    assert length(non_metrics) == 2

    Enum.each(metrics, fn query ->
      expression = resolve_variables(query["expression"])
      assert {:ok, _} = Parser.parse(expression), "#{query["source"]}: #{expression}"
    end)

    [logs] = Enum.filter(non_metrics, &(&1["datasource"] == "$logs_datasource"))
    assert {:ok, _} = Pulse.LogQL.Parser.parse(resolve_variables(logs["expression"]))
  end

  # This is deliberately representative syntax only, not Grafana's variable
  # renderer. Real interval values and regex interpolation need client tests.
  defp resolve_variables(expression) do
    Regex.replace(~r/\$\{[^}]+\}|\$[A-Za-z_]\w*/, expression, fn variable ->
      if String.contains?(variable, ["interval", "range", "window"]), do: "5m", else: "1"
    end)
  end
end
