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
end
