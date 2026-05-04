defmodule Tuist.Kura.SpecsTest do
  use ExUnit.Case, async: true

  alias Tuist.Kura.Specs

  test "all/0 returns the small/medium/large catalog" do
    assert Enum.map(Specs.all(), & &1.id) == [:small, :medium, :large]
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

  test "bandwidth/1 returns Cilium-shaped caps per spec" do
    assert Specs.bandwidth(:small) == %{ingress: "100M", egress: "100M"}
    assert Specs.bandwidth(:medium) == %{ingress: "250M", egress: "250M"}
    assert Specs.bandwidth(:large) == %{ingress: "500M", egress: "500M"}
    assert Specs.bandwidth(:nonsense) == nil
  end
end
