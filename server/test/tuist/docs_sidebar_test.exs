defmodule Tuist.Docs.SidebarTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.Docs
  alias Tuist.Docs.CLI
  alias Tuist.Docs.Page
  alias Tuist.Docs.Sidebar

  test "tree returns a non-empty list of groups" do
    stub(CLI, :sidebar_items, fn -> [] end)

    tree = Sidebar.tree()
    assert [_ | _] = tree
  end

  test "all sidebar slugs correspond to actual docs pages" do
    stub(CLI, :sidebar_items, fn -> [] end)

    stub(CLI, :get_page, fn
      "/en/cli/debugging" = slug ->
        %Page{slug: slug, title: "Debugging", body: "Debugging", source_path: "test://cli/debugging"}

      "/en/cli/directories" = slug ->
        %Page{slug: slug, title: "Directories", body: "Directories", source_path: "test://cli/directories"}

      "/en/cli/shell-completions" = slug ->
        %Page{
          slug: slug,
          title: "Shell completions",
          body: "Shell completions",
          source_path: "test://cli/shell-completions"
        }

      _slug ->
        nil
    end)

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
