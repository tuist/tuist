defmodule Atlas.Accounts.LifecycleTest do
  use ExUnit.Case, async: true

  alias Atlas.Accounts.Lifecycle

  test "maps customer segment to a Customer lifecycle" do
    lifecycle = Lifecycle.from_segment(:customer)

    assert lifecycle.key == "customer"
    assert lifecycle.label == "Customer"
    assert lifecycle.color == "success"
  end

  test "maps prospect and lead segments" do
    assert Lifecycle.label(:prospect) == "Prospect"
    assert Lifecycle.label(:lead) == "Lead"
  end

  test "falls back to Unknown for unrecognized segments" do
    assert Lifecycle.label(nil) == "Unknown"
    assert Lifecycle.label(:other) == "Unknown"
  end
end
