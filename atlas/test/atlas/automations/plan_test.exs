defmodule Atlas.Automations.PlanTest do
  use Atlas.DataCase, async: true

  alias Atlas.Automations.Plan

  test "rejects forward, cyclic, malformed, and undeclared references" do
    for reference <- ["steps.future.title", "steps.current.title", "secrets.token", 42] do
      assert {:error, _} =
               Plan.compile(%{
                 "steps" => [
                   %{"id" => "current", "behavior" => "core.value", "inputs" => %{"value" => %{"$ref" => reference}}}
                 ]
               })
    end

    assert {:error, _} =
             Plan.compile(%{
               "steps" => [%{"id" => "one", "behavior" => "core.value", "inputs" => %{}, "shell" => "echo unsafe"}]
             })
  end

  test "bounds step count and rejects duplicate IDs" do
    step = %{"id" => "one", "behavior" => "core.value", "inputs" => %{}}
    assert {:error, _} = Plan.compile(%{"steps" => []})
    assert {:error, _} = Plan.compile(%{"steps" => List.duplicate(step, 33)})
    assert {:error, _} = Plan.compile(%{"steps" => [step, step]})
    assert {:error, _} = Plan.compile(%{"steps" => [Map.put(step, "behavior", "shell.execute")]})
  end

  test "resolves nested values and null without substituting missing values" do
    assert {:ok, %{"list" => [nil, 7]}} =
             Plan.resolve(
               %{"list" => [%{"$ref" => "input.empty"}, %{"$ref" => "steps.first.count"}]},
               %{"empty" => nil},
               %{"first" => %{"count" => 7}}
             )

    assert {:error, _} = Plan.resolve(%{"$ref" => "input.missing"}, %{}, %{})
  end
end
