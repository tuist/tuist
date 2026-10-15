defmodule Tuist.OnceEvents.PresentationTest do
  use ExUnit.Case, async: true

  alias Tuist.OnceEvents.Presentation

  test "old and malformed optional metadata stays absent" do
    for value <- [nil, "bad", [], %{}, %{"platforms" => nil}, %{"package" => %{"name" => "missing ecosystem"}}] do
      assert Presentation.normalize(value) == nil
    end
  end

  test "future namespaces and usages survive without atom creation or label parsing" do
    value = %{
      "package" => %{
        "ecosystem" => "future",
        "name" => "lib",
        "version" => "v0.0.0-pseudo",
        "revision" => "abcdef",
        "digest" => "sha256:123",
        "origin" => "registry"
      },
      "platforms" => [
        %{"scheme" => "future", "id" => "native-target", "label" => "Friendly\nname", "usage" => "future-role"}
      ],
      "context" => [%{"key" => "future.level", "value" => "17", "label" => "<b>17</b>"}],
      "raw_environment" => %{"SECRET" => "must not survive"}
    }

    normalized = Presentation.normalize(value)
    assert normalized["package"]["version"] == "v0.0.0-pseudo"
    assert normalized["package"]["revision"] == "abcdef"

    assert normalized["platforms"] == [
             %{"scheme" => "future", "id" => "native-target", "label" => "Friendly name", "usage" => "future-role"}
           ]

    refute Map.has_key?(normalized, "raw_environment")
    assert Presentation.normalize(normalized) == normalized
  end

  test "entry and total bounds drop whole stable identifiers instead of changing identity" do
    contexts = Enum.map(1..20, &%{"key" => "future.key#{&1}", "value" => String.duplicate("x", 256)})
    normalized = Presentation.normalize(%{"context" => contexts})
    assert length(normalized["context"]) <= 8
    assert Enum.all?(normalized["context"], &(&1["value"] == String.duplicate("x", 256)))

    bytes =
      normalized["context"] |> Enum.flat_map(&Map.values/1) |> Enum.map(&byte_size/1) |> Enum.sum()

    assert bytes <= 2048
    assert Presentation.normalize(%{"platforms" => [%{"scheme" => "custom", "id" => String.duplicate("x", 257)}]}) == nil
    assert Presentation.normalize(%{"context" => [%{"key" => "custom.mode", "value" => "bad\0value"}]}) == nil
  end
end
