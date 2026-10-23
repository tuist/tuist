defmodule TuistWeb.Noora.Pages.Introduction do
  @moduledoc false
  use TuistWeb.Noora.Page,
    title: "Noora",
    nav_title: "Introduction",
    slug: "introduction",
    description:
      "Tuist's design system for Phoenix LiveView. The components and tokens behind the Tuist dashboard and website."

  alias TuistWeb.Noora.Pages

  def content(assigns) do
    assigns =
      assign(assigns, component_count: length(Pages.components()))

    ~H"""
    <section data-part="section">
      <div data-part="cards">
        <.link navigate={Pages.path(Pages.Installation)}>
          <.download />
          <strong>Installation</strong>
          <span>Add Noora to a Phoenix application in four steps.</span>
        </.link>
        <.link navigate={Pages.path(Pages.Button)}>
          <.layout_grid />
          <strong>Components</strong>
          <span>{@component_count} Phoenix components, with live examples and their full API.</span>
        </.link>
        <.link navigate={Pages.path(Pages.Colors)}>
          <.chart_donut_4 />
          <strong>Colors</strong>
          <span>The color scales behind every component.</span>
        </.link>
        <.link navigate={Pages.path(Pages.Typography)}>
          <.file_text />
          <strong>Typography</strong>
          <span>Type styles for display, headings, body text, and code.</span>
        </.link>
      </div>
    </section>
    """
  end
end
