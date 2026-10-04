defmodule TuistEx.Analytics.MetadataTest do
  use ExUnit.Case, async: true

  alias TuistEx.Analytics.Metadata

  test "returns nil when no tags or values are configured" do
    assert Metadata.collect(environment: fn _ -> nil end) == nil
  end

  test "reads tags and values from TUIST_TAGS and TUIST_VALUES" do
    environment = fn
      "TUIST_TAGS" -> "nightly, release "
      "TUIST_VALUES" -> "ticket=PROJ-123, owner=infra"
      _ -> nil
    end

    assert %{tags: tags, values: values} = Metadata.collect(environment: environment)
    assert tags == ["nightly", "release"]
    assert values == %{"ticket" => "PROJ-123", "owner" => "infra"}
  end

  test "reads tags and values from the project config it is given" do
    assert %{tags: ["nightly"], values: %{"team" => "platform"}} =
             Metadata.collect(
               environment: fn _ -> nil end,
               project_config: [tags: ["nightly"], values: %{"team" => "platform"}]
             )
  end

  test "accepts inline options and de-duplicates tags" do
    environment = fn _ -> nil end

    assert %{tags: ["a", "b"], values: %{"k" => "v"}} =
             Metadata.collect(
               environment: environment,
               tag: "a",
               tag: "a",
               tag: "b",
               value: "k=v"
             )
  end

  test "environment overrides runtime options" do
    environment = fn
      "TUIST_TAGS" -> "prod"
      "TUIST_VALUES" -> "ticket=PROJ-999"
      _ -> nil
    end

    assert %{tags: tags, values: values} =
             Metadata.collect(
               environment: environment,
               tag: "staging",
               value: "ticket=PROJ-100"
             )

    assert "prod" in tags
    assert "staging" in tags
    assert values["ticket"] == "PROJ-999"
  end

  test "leaves out tags and values the server would refuse the whole report for" do
    environment = fn
      "TUIST_TAGS" ->
        "nightly,bad tag,#{String.duplicate("t", 51)},release_2"

      "TUIST_VALUES" ->
        "ticket=SHOP-42,empty=,#{String.duplicate("k", 51)}=x,long=#{String.duplicate("v", 501)}"

      _ ->
        nil
    end

    assert Metadata.collect(environment: environment) == %{
             tags: ["nightly", "release_2"],
             values: %{"ticket" => "SHOP-42"}
           }
  end

  test "keeps at most the number of tags and values the server accepts" do
    environment = fn
      "TUIST_TAGS" -> Enum.map_join(1..60, ",", &"tag-#{&1}")
      "TUIST_VALUES" -> Enum.map_join(1..25, ",", &"key#{&1}=value")
      _ -> nil
    end

    assert %{tags: tags, values: values} = Metadata.collect(environment: environment)
    assert length(tags) == 50
    assert map_size(values) == 20
  end
end
