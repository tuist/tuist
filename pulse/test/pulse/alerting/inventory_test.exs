Code.require_file("../../../plans/alerting/inventory.exs", __DIR__)

defmodule Pulse.Alerting.InventoryTest do
  use Pulse.Test.Case, async: true

  alias Pulse.Alerting.Canonical
  alias Pulse.Alerting.Graph
  alias Pulse.Plans.AlertInventory

  @root Path.expand("../../../plans/alerting", __DIR__)
  setup do
    %{
      snapshot: Pulse.JSON.decode!(File.read!(Path.join(@root, "grafana-rule-inventory.json"))),
      notifications: Pulse.JSON.decode!(File.read!(Path.join(@root, "notification-inventory.json")))
    }
  end

  test "complete inventory digest, graph and notification references are valid", ctx do
    assert {:ok, %{"prometheus" => 105, "loki" => 16, "clickhouse" => 2, "expression" => 107}} =
             AlertInventory.validate(ctx.snapshot, ctx.notifications)

    assert AlertInventory.render(ctx.snapshot["rules"]) == File.read!(Path.join(@root, "coverage-matrix.md"))
  end

  test "original field loss and wrong keep-firing spelling fail closed", ctx do
    [first | rest] = ctx.snapshot["rules"]

    for altered <- [Map.delete(first, "keep_firing_for"), Map.put(first, "keepFiringFor", first["keep_firing_for"])] do
      assert {:error, :invalid_inventory} =
               AlertInventory.validate(Map.put(ctx.snapshot, "rules", [altered | rest]), ctx.notifications)
    end
  end

  test "missing references and cycles are rejected even with a correctly recomputed digest", ctx do
    for dependency <- ["missing_ref", :self] do
      rules =
        Enum.map(ctx.snapshot["rules"], fn rule ->
          Map.update!(rule, "data", fn nodes ->
            Enum.map(nodes, fn node ->
              if node["model"]["type"] == "threshold",
                do: put_in(node, ["model", "expression"], if(dependency == :self, do: node["refId"], else: dependency)),
                else: node
            end)
          end)
        end)

      original =
        Enum.map(rules, fn rule ->
          rule
          |> Map.delete("evaluation_interval_seconds")
          |> Map.update!("data", &Enum.map(&1, fn n -> Map.delete(n, "source_type") end))
        end)

      snapshot =
        ctx.snapshot
        |> Map.put("rules", rules)
        |> put_in(["provenance", "original_rules_sha256"], Canonical.hash(original))

      assert {:error, :invalid_inventory} = AlertInventory.validate(snapshot, ctx.notifications)
    end
  end

  test "braced cross-source references remain present", ctx do
    rule = Enum.find(ctx.snapshot["rules"], &(&1["uid"] == "sm-failed-executions-5m-15b8b2b7"))
    assert Enum.sort(Enum.uniq(Enum.map(rule["data"], & &1["source_type"]))) == ["expression", "loki", "prometheus"]

    assert Enum.find(rule["data"], &(&1["refId"] == "condition"))["model"]["expression"] ==
             "${executions} >= ${threshold}"

    assert :ok = Graph.validate(rule)
  end
end
