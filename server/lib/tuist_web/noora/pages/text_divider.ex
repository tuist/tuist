defmodule TuistWeb.Noora.Pages.TextDivider do
  @moduledoc false
  use TuistWeb.Noora.Page,
    title: "Text divider",
    description: "Separates content with a short, muted label and no line.",
    components: [{Noora.TextDivider, :text_divider}],
    guidelines: [
      "Use a text divider to name the next group of content, such as a time period in a list.",
      "The text renders exactly as passed. Write it in the case you want to show.",
      "It takes only `text` and accepts no other attributes. For a rule with a label, use the line divider with `text`."
    ]

  example "Default", layout: :column do
    ~H"""
    <.text_divider text="or" />
    """
  end

  example "Group label", description: "Names the group of content that follows.", layout: :column do
    ~H"""
    <.text_divider text="Today" />
    <.button label="tuist build App" variant="secondary" />
    <.text_divider text="Yesterday" />
    <.button label="tuist test AppTests" variant="secondary" />
    """
  end

  example "Between options", description: "Separates two ways to do the same thing.", layout: :column do
    ~H"""
    <.button label="Continue with GitHub" variant="secondary" />
    <.text_divider text="or" />
    <.button label="Continue with email" variant="secondary" />
    """
  end
end
