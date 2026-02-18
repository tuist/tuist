defmodule TuistWeb.Helpers.OpenGraphTest do
  use ExUnit.Case, async: true

  alias TuistWeb.Helpers.OpenGraph

  test "resolved_head_image/1 returns generated URL for public project pages" do
    assigns = %{
      selected_account: %{name: "tuist"},
      selected_project: %{name: "tuist", visibility: :public, build_system: :xcode},
      head_title: "Compilation · tuist/tuist · Tuist"
    }

    head_image = OpenGraph.resolved_head_image(assigns)

    assert head_image =~ "/tuist/tuist/og/"
    assert URI.parse(head_image).query |> URI.decode_query() |> Map.get("title") == "Compilation"
  end

  test "resolved_head_image/1 falls back to default card for non-public projects" do
    assigns = %{
      selected_account: %{name: "tuist"},
      selected_project: %{name: "tuist", visibility: :private, build_system: :xcode},
      head_title: "Compilation · tuist/tuist · Tuist"
    }

    assert OpenGraph.resolved_head_image(assigns) ==
             Tuist.Environment.app_url(path: "/images/open-graph/card.jpeg")
  end

  test "resolved_twitter_card/1 uses a large image card for public project pages" do
    assert OpenGraph.resolved_twitter_card(%{
             selected_project: %{visibility: :public}
           }) == "summary_large_image"
  end

  test "resolved_twitter_card/1 defaults to summary outside project pages" do
    assert OpenGraph.resolved_twitter_card(%{}) == "summary"
  end

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

  test "semantic_key_values/3 falls back to defaults when values are blank" do
    assert [
             %{key: "Page", value: "Overview"},
             %{key: "Section", value: "Project"},
             %{key: "Focus", value: "Overview"}
           ] = OpenGraph.semantic_key_values("", "  ", nil)
  end
end
