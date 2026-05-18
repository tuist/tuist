defmodule Tuist.Docs.SidebarTest do
  use ExUnit.Case, async: true

  alias Tuist.Docs
  alias Tuist.Docs.Sidebar

  test "tree returns a non-empty list of groups" do
    tree = Sidebar.tree()
    assert length(tree) > 0
  end

  test "all sidebar slugs correspond to actual docs pages" do
    slugs = collect_slugs(Sidebar.tree())

    for slug <- slugs do
      assert Docs.get_page(slug) != nil, "Sidebar references non-existent page: #{slug}"
    end
  end

  test "item_active? returns true for matching slug" do
    item = %Sidebar.Item{label: "Test", slug: "/en/guides/install-tuist"}
    assert Sidebar.item_active?(item, "/en/guides/install-tuist")
    refute Sidebar.item_active?(item, "/en/guides/other")
  end

  test "item_or_children_active? returns true for child match" do
    item = %Sidebar.Item{
      label: "Parent",
      slug: "/en/parent",
      items: [
        %Sidebar.Item{label: "Child", slug: "/en/parent/child"}
      ]
    }

    assert Sidebar.item_or_children_active?(item, "/en/parent")
    assert Sidebar.item_or_children_active?(item, "/en/parent/child")
    refute Sidebar.item_or_children_active?(item, "/en/other")
  end

  defp collect_slugs(groups) do
    Enum.flat_map(groups, fn group ->
      Enum.flat_map(group.items, &collect_item_slugs/1)
    end)
  end

  defp collect_item_slugs(%{slug: slug, items: items}) do
    own = if slug, do: [slug], else: []
    own ++ Enum.flat_map(items, &collect_item_slugs/1)
  end
end
