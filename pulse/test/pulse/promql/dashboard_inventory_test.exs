defmodule Pulse.PromQL.DashboardInventoryTest do
  use Pulse.Test.Case, async: true

  alias Pulse.PromQL.Parser

  test "the versioned Tuist dashboard inventory parses in its actual query language" do
    fixture = File.read!(Path.expand("../../fixtures/promql/tuist_dashboards.json", __DIR__)) |> JSON.decode!()

    failures =
      Enum.flat_map(fixture["queries"], fn query ->
        parser = if query["language"] == "promql", do: Parser, else: Pulse.LogQL.Parser

        case parser.parse(query["expression"]) do
          {:ok, _} -> []
          error -> [{query["source"], query["expression"], error}]
        end
      end)

    assert failures == [], inspect(failures, pretty: true, limit: :infinity)
  end
end
