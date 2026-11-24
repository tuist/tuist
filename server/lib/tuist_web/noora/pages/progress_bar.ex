defmodule TuistWeb.Noora.Pages.ProgressBar do
  @moduledoc false
  use TuistWeb.Noora.Page,
    title: "Progress bar",
    description: "Shows how much of a limit or total has been used, such as plan usage or test coverage.",
    components: [{Noora.ProgressBar, :progress_bar}],
    guidelines: [
      "Pass integers for `value` and `max`. The bar fills to `value / max` and stops at full when `value` is larger.",
      "Add a `title` to show the header with the current value and the maximum. Without a title, only the bar renders.",
      "Use `value_label` and `max_label` to format large numbers or sizes for the reader. The bar still measures itself with `value` and `max`.",
      "Use the `description` slot for a short explanation or a link below the bar."
    ]

  example "Default", description: "Without a title, only the bar renders.", layout: :column do
    ~H"""
    <.progress_bar value={68} max={100} />
    """
  end

  example "With title", description: "The header shows the title, the current value, and the maximum.", layout: :column do
    ~H"""
    <.progress_bar value={142} max={200} title="Remote cache hits:" />
    """
  end

  example "Formatted values",
    description: "`value_label` and `max_label` replace the numbers shown in the header.",
    layout: :column do
    ~H"""
    <.progress_bar
      value={3_650_722_816}
      max={10_737_418_240}
      value_label="3.4 GB"
      max_label="10 GB"
      title="Cache egress:"
    />
    <.progress_bar
      value={18_420}
      max={50_000}
      value_label="18.4K"
      max_label="50K"
      title="Passing test cases:"
    />
    """
  end

  example "Over the limit",
    description: "A value above the maximum fills the bar without overflowing it.",
    layout: :column do
    ~H"""
    <.progress_bar
      value={1_240}
      max={1_000}
      value_label="1,240"
      max_label="1,000"
      title="Runner minutes:"
    />
    """
  end

  example "With description", description: "The `description` slot renders below the bar.", layout: :column do
    ~H"""
    <.progress_bar value={142} max={200} title="Remote cache hits:">
      <:description>
        <.link_button
          href="https://tuist.dev/pricing"
          label="Learn more about remote cache hits"
          variant="primary"
          size="medium"
          underline
        />
      </:description>
    </.progress_bar>
    """
  end
end
