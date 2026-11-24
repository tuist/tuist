defmodule TuistWeb.Noora.Pages.Icons do
  @moduledoc false
  use TuistWeb.Noora.Page,
    title: "Icons",
    description:
      "Every icon in Noora, at 24, 20, 16, 14, and 12px. Listed in development only, while the set is being reworked."

  @groups [
    {"line", "Line icons", "Outlined from 2px lines on a 24px grid."},
    {"brand", "Brand", "Logos, named `brand_*`."},
    {"custom", "Custom", "Artwork drawn for Noora, named `custom_*`."}
  ]

  @sizes ~w(24 20 16 14 12)

  @context_icons ~w(search filter settings git_branch bell user folder lock)

  def content(assigns) do
    assigns =
      assign(assigns,
        sizes: @sizes,
        context_icons: @context_icons,
        groups:
          for {id, title, description} <- @groups do
            %{id: id, title: title, description: description, names: Enum.filter(Noora.Icon.names(), &(group(&1) == id))}
          end
      )

    ~H"""
    <section id="in-context" data-part="section">
      <h2><a href="#in-context">In context</a></h2>
      <p>Icons beside the text they usually sit next to.</p>
      <div data-part="icon-context">
        <div data-part="row">
          <.button variant="primary" size="medium" label="New project">
            <:icon_left><.icon name="plus" /></:icon_left>
          </.button>
          <.button variant="secondary" size="medium" label="Filter">
            <:icon_left><.icon name="filter" /></:icon_left>
          </.button>
          <.button variant="secondary" size="medium" label="Download">
            <:icon_left><.icon name="download" /></:icon_left>
          </.button>
          <.button variant="secondary" size="small" label="Copy">
            <:icon_left><.icon name="copy" /></:icon_left>
          </.button>
          <.button variant="destructive" size="medium" label="Delete">
            <:icon_left><.icon name="trash" /></:icon_left>
          </.button>
        </div>
        <ul data-part="list">
          <li :for={name <- @context_icons}>
            <.icon name={name} />
            <span>{name |> String.replace("_", " ") |> String.capitalize()}</span>
          </li>
        </ul>
      </div>
    </section>
    <section :for={group <- @groups} id={group.id} data-part="section">
      <h2><a href={"##{group.id}"}>{group.title} ({length(group.names)})</a></h2>
      <p>{group.description}</p>
      <div data-part="icon-tiles">
        <div :for={name <- group.names}>
          <div data-part="icon-sizes">
            <span :for={size <- @sizes} data-size={size}><.icon name={name} /></span>
          </div>
          <code title={name}>{name}</code>
        </div>
      </div>
    </section>
    """
  end

  defp group("brand_" <> _), do: "brand"
  defp group("custom_" <> _), do: "custom"
  defp group(_name), do: "line"
end
