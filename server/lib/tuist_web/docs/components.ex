defmodule TuistWeb.Docs.Components do
  @moduledoc false
  use TuistWeb, :html
  use Noora

  alias Tuist.Docs.Sidebar

  @group_icons %{
    "Guides" => "category",
    "Tutorials" => "book",
    "Features" => "apps",
    "Integrations" => "asset",
    "Server" => "server",
    "Contributors" => "users",
    "References" => "file_text"
  }

  attr :current_slug, :string, required: true
  attr :headings, :list, required: true
  slot :inner_block, required: true

  def layout(assigns) do
    assigns = assign(assigns, :tree, Sidebar.tree())
    page_layout(assigns)
  end

  embed_templates "components/*"

  defp group_icon(label), do: Map.get(@group_icons, label, "file")

  defp slugify(label) do
    label
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
  end
end
