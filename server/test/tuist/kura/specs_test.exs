defmodule Tuist.Kura.SpecsTest do
  use ExUnit.Case, async: true

  alias Tuist.Kura.Specs

  test "all/0 returns the small/medium/large catalog" do
    assert Enum.map(Specs.all(), & &1.id) == [:small, :medium, :large]
  end

  test "every spec carries a customer-facing label and description" do
    for %Specs{label: label, description: description} <- Specs.all() do
      assert is_binary(label) and label != ""
      assert is_binary(description) and description != ""
    end
  end

  test "get/1 returns the matching spec" do
    assert %Specs{id: :medium, label: "Medium"} = Specs.get(:medium)
    assert Specs.get(:huge) == nil
  end

  test "default_volume_gi/1 returns sane defaults" do
    assert Specs.default_volume_gi(:small) == 50
    assert Specs.default_volume_gi(:medium) == 200
    assert Specs.default_volume_gi(:large) == 500
    assert Specs.default_volume_gi(:nonsense) == nil
  end
end
