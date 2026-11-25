defmodule TuistWeb.Noora.Pages.ContentDivider do
  @moduledoc false
  use TuistWeb.Noora.Page,
    title: "Content divider",
    description: "Separates groups of content with a horizontal line, a labeled line, or a label alone.",
    components: [{Noora.ContentDivider, :content_divider}],
    guidelines: [
      "Use a divider between groups of related items, such as sections of a menu or entries in a list, not between every item.",
      "The divider spans the full width of its container. Wrap it or the surrounding content to control its length.",
      "Add `text` to label the break, such as or between two ways to sign in. The line splits around the label.",
      "Use the `text` variant to name the next group of content without a line, such as a time period in a list. It needs `text`.",
      "The label always renders in uppercase, whatever case you pass."
    ]

  example "Line", description: "The default variant: a one-pixel line across the container.", layout: :column do
    ~H"""
    <.content_divider />
    """
  end

  example "Line with text", description: "The label sits in the middle with the line on both sides.", layout: :column do
    ~H"""
    <.content_divider text="or" />
    """
  end

  example "Text", description: "A muted label without a line.", layout: :column do
    ~H"""
    <.content_divider variant="text" text="or" />
    """
  end
end
