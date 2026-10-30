defmodule TuistWeb.Components.ResourceCardTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias TuistWeb.Components.ResourceCard

  test "renders the project-card artwork as a non-focusable decoration" do
    html = render_component(&ResourceCard.background/1, id: "workload-42")
    document = Floki.parse_fragment!(html)

    assert Floki.attribute(document, "svg", "class") == ["tuist-resource-card-background"]
    assert Floki.attribute(document, "svg", "aria-hidden") == ["true"]
    assert Floki.attribute(document, "svg", "focusable") == ["false"]
    assert Floki.attribute(document, "svg", "viewbox") == ["0 0 292 196"]
    assert length(Floki.find(document, "g path")) == 8
    assert length(Floki.find(document, "g circle")) == 3
  end

  test "keeps SVG identifiers stable when the caller supplies a card identifier" do
    first = render_component(&ResourceCard.background/1, id: "workload-42")
    second = render_component(&ResourceCard.background/1, id: "workload-42")
    assert first == second

    document = Floki.parse_fragment!(first)
    assert Floki.attribute(document, "mask", "id") == ["mask0_workload-42"]
    assert Floki.attribute(document, "g", "mask") == ["url(#mask0_workload-42)"]
    assert Floki.attribute(document, "mask rect", "fill") == ["url(#paint0_radial_workload-42)"]
  end

  test "namespaces definitions for multiple project or workload cards" do
    for identifiers <- [["workload-42", "workload-43"], [nil, nil]] do
      html = Enum.map_join(identifiers, fn id -> render_component(&ResourceCard.background/1, id: id) end)
      document = Floki.parse_fragment!(html)
      ids = Floki.attribute(document, "[id]", "id")
      assert length(ids) == MapSet.size(MapSet.new(ids))
      assert length(Floki.find(document, "mask")) == 2
    end
  end
end
