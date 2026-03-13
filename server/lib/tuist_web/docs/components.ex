defmodule TuistWeb.Docs.Components do
  @moduledoc false
  use TuistWeb, :html
  use Noora

  alias Tuist.Docs.Paths
  alias Tuist.Docs.Sidebar

  @group_icons %{
    "Guides" => "books",
    "Tutorials" => "book",
    "Builds" => "versions",
    "Tests" => "subtask",
    "Artifacts" => "package",
    "Other features" => "apps",
    "Integrations" => "asset",
    "Server" => "server",
    "Contributors" => "users",
    "Examples" => "folder",
    "References" => "file_text"
  }

  attr :current_slug, :string, required: true
  attr :tab, :atom, required: true
  attr :headings, :list, required: true
  attr :markdown, :string, required: true
  slot :inner_block, required: true

  def layout(assigns) do
    assigns = assign(assigns, :tree, Sidebar.tree_for_tab(assigns.tab))
    page_layout(assigns)
  end

  embed_templates "components/*"

  defp group_icon(label), do: Map.get(@group_icons, label, "file")

  @item_icon_srcs %{
    "xcode" => "/docs/images/guides/features/xcode-icon.png",
    "gradle" => "/docs/images/guides/features/gradle-icon.svg"
  }

  defp item_icon_src(icon), do: Map.fetch!(@item_icon_srcs, icon)

  defp docs_path(slug), do: Paths.public_path_from_slug(slug)

  defp slugify(label) do
    label
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
  end
end
