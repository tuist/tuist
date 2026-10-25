defmodule Tuist.Builds.MetadataTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.Builds.Build
  alias Tuist.Builds.Metadata

  test "the existing map accepts future keys and retains string values" do
    values = Map.new(1..64, &{"future.#{&1}", "#{&1}"})
    assert :ok = Build.validate_custom_metadata([], values)
    assert {:error, _} = Build.validate_custom_metadata([], Map.put(values, "one.more", "65"))
    assert {:error, _} = Build.validate_custom_metadata([], %{"number" => 28})
  end

  test "recognition only controls display and never discards unknown or invalid values" do
    values = %{
      "tuist.cpu.available_processors" => "28",
      "tuist.gradle.max_workers" => "not available",
      "tuist.future.key" => "future value",
      "ticket" => "BUILD-123"
    }

    {recognized, raw} = Metadata.partition(values)
    assert recognized == [{"tuist.cpu.available_processors", "28"}]
    assert Map.new(recognized ++ raw) == values
    assert Enum.count(recognized ++ raw) == map_size(values)
  end

  test "numeric recognition preserves missing evidence and bounds parsed values" do
    for value <- ["", "0", "-1", "1.5", "123invalid", "9007199254740992"] do
      assert is_nil(Metadata.kind("tuist.jvm.max_heap_bytes", value))
    end

    assert Metadata.kind("tuist.jvm.max_heap_bytes", "1024") == :bytes
  end

  test "extended advertisement is separate from acceptance and defaults to legacy support" do
    stub(Tuist.Environment, :expanded_build_metadata_enabled?, fn -> false end)
    assert Metadata.advertised_limit() == 20
    assert Metadata.limit() == 64
    stub(Tuist.Environment, :expanded_build_metadata_enabled?, fn -> true end)
    assert Metadata.advertised_limit() == 64
  end
end
