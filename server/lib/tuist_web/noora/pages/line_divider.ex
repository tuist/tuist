defmodule TuistWeb.Noora.Pages.LineDivider do
  @moduledoc false
  use TuistWeb.Noora.Page,
    title: "Line divider",
    description: "Separates groups of content with a horizontal rule, optionally labeled.",
    components: [{Noora.LineDivider, :line_divider}],
    guidelines: [
      "Use a divider between groups of related items, such as sections of a menu or entries in a list, not between every item.",
      "The divider spans the full width of its container. Wrap it or the surrounding content to control its length.",
      "Add `text` to label the break, such as or between two ways to sign in. The line splits around the label.",
      "For a label without a line, use the text divider."
    ]

  example "Default", description: "A one-pixel rule across the container.", layout: :column do
    ~H"""
    <.line_divider />
    """
  end

  example "With text", description: "The label sits in the middle with the line on both sides.", layout: :column do
    ~H"""
    <.line_divider text="or" />
    """
  end

  example "Between groups", description: "Separates groups of actions, as in a menu.", layout: :column do
    ~H"""
    <.button label="Project settings" variant="secondary" />
    <.button label="Members" variant="secondary" />
    <.line_divider />
    <.button label="Delete project" variant="destructive" />
    """
  end

  example "Between options", description: "Separates two ways to do the same thing.", layout: :column do
    ~H"""
    <.button label="Continue with GitHub" variant="secondary" />
    <.line_divider text="or" />
    <.button label="Continue with email" variant="secondary" />
    """
  end
end
