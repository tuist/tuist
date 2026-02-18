defmodule TuistWeb.Helpers.OpenGraphTest do
  use ExUnit.Case, async: true

  alias TuistWeb.Helpers.OpenGraph

  test "og_image_assigns/0 returns default dashboard assigns" do
    assert [
             head_twitter_card: "summary_large_image"
           ] = OpenGraph.og_image_assigns()
  end

  test "og_image_assigns/1 uses explicit key values" do
    key_values = OpenGraph.semantic_key_values("Bundles", "Binary Size", "Bundles")

    assert [
             head_twitter_card: "summary_large_image",
             head_open_graph_key_values: [
               %{key: "Page", value: "Bundles"},
               %{key: "Section", value: "Binary Size"},
               %{key: "Focus", value: "Bundles"}
             ]
           ] = OpenGraph.og_image_assigns(key_values)
  end

  test "og_image_assigns/1 falls back to defaults for non-list values" do
    assert [
             head_twitter_card: "summary_large_image"
           ] = OpenGraph.og_image_assigns("invalid")
  end

  test "semantic_key_values/3 falls back to defaults when values are blank" do
    assert [
             %{key: "Page", value: "Overview"},
             %{key: "Section", value: "Project"},
             %{key: "Focus", value: "Overview"}
           ] = OpenGraph.semantic_key_values("", "  ", nil)
  end
end
