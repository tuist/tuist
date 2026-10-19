defmodule TuistWeb.Components.PageFrame do
  @moduledoc """
  The shared frame for a dashboard page: an optional header (title, subtitle and
  actions), an optional filters row and the page body.

  The frame owns the page gutters and width. It reads the `--layout-page-*`
  tiers defined on `.layout__content` (see `assets/app/css/layouts.css`), so
  pages no longer hardcode their own padding. Pick the `compact` layout for
  settings-style pages and keep `standard` for analytics pages.

  Body content renders as direct children of the frame, so page CSS that
  targets `#page-id > [data-part="..."]` keeps working after migrating.
  """
  use Phoenix.Component

  attr(:id, :string, required: true)
  attr(:title, :string, default: nil)
  attr(:subtitle, :string, default: nil)
  attr(:layout, :string, default: "standard", values: ~w(standard compact))
  attr(:class, :any, default: nil)
  attr(:rest, :global)
  slot(:actions)
  slot(:filters)
  slot(:inner_block, required: true)

  def page_frame(assigns) do
    ~H"""
    <div id={@id} class={["tuist-page", @class]} data-layout={@layout} {@rest}>
      <header :if={@title || @actions != []} data-part="page-header">
        <div :if={@title} data-part="title-group">
          <h1 data-part="title">{@title}</h1>
          <span :if={@subtitle} data-part="subtitle">{@subtitle}</span>
        </div>
        <div :if={@actions != []} data-part="page-actions">{render_slot(@actions)}</div>
      </header>
      <div :if={@filters != []} data-part="page-filters">{render_slot(@filters)}</div>
      {render_slot(@inner_block)}
    </div>
    """
  end
end
