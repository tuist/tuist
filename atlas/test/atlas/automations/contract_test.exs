defmodule Atlas.Automations.ContractTest do
  use ExUnit.Case, async: true

  alias Atlas.Automations.Contract

  test "rejects reference amplification before encoding a large expanded payload" do
    shared = %{"payload" => String.duplicate("x", 20_000)}
    amplified = %{"copies" => List.duplicate(shared, 4000)}
    refute Contract.within_budget?(amplified, 65_536)
    assert {:error, _} = Contract.validate(%{"type" => "object"}, amplified)
  end

  test "bounds nesting and accounts for JSON escaping" do
    nested = Enum.reduce(1..40, %{}, fn _, value -> %{"nested" => value} end)
    refute Contract.within_budget?(nested, 65_536)
    refute Contract.within_budget?(%{"control" => String.duplicate(<<0>>, 12_000)}, 65_536)
    assert :ok = Contract.validate(%{"type" => "object"}, %{"value" => [true, false, nil, 42, "text"]})
  end
end
