defmodule TuistWeb.Noora.Pages.TextArea do
  @moduledoc false
  use TuistWeb.Noora.Page,
    title: "Text area",
    description: "Collects text that spans several lines, such as a message template or a query.",
    components: [{Noora.TextArea, :text_area}],
    guidelines: [
      "`max_length` caps the text and defaults to 200 characters. Raise it for long content, and hide the counter with `show_character_count={false}` when people are unlikely to reach the limit.",
      "The character count is computed from `value` on the server. It changes as people type only when a `phx-change` handler sends the new value back.",
      "Set `rows` to fit the content you expect, so people see most of it without scrolling.",
      "`error` replaces the hint and outlines the field. Pass `show_error_message={false}` to keep the outline without the message.",
      "Inside a form, pass `field`. The text area then takes its id, name, value, and first error from the form field."
    ]

  example "Default", description: "Shows the character count against `max_length`.", layout: :column do
    ~H"""
    <.text_area
      id="text-area-default"
      name="message"
      label="Message template"
      placeholder="Enter message template..."
    />
    """
  end

  example "Label and hint", layout: :column do
    ~H"""
    <.text_area
      id="text-area-label-hint"
      name="description"
      label="Description"
      sublabel="(Optional)"
      placeholder="What this automation does and who it notifies"
      hint="Shown to everyone in the organization."
    />
    """
  end

  example "Character limit", description: "Raise `max_length` for long content, or hide the counter.", layout: :column do
    ~H"""
    <.text_area
      id="text-area-limit"
      name="message"
      label="Slack message"
      max_length={2000}
      value="Flaky test detected in AppTests: the test failed and passed on the same commit."
    />
    <.text_area
      id="text-area-no-count"
      name="query"
      label="Query"
      rows={8}
      max_length={10_000}
      show_character_count={false}
      placeholder="SELECT id, name FROM accounts ORDER BY inserted_at DESC LIMIT 50;"
    />
    """
  end

  example "Error", layout: :column do
    ~H"""
    <.text_area
      id="text-area-error"
      name="message"
      label="Message template"
      value=""
      error="Enter a message to send"
      required
      show_required
    />
    """
  end

  example "Disabled", description: "Hides the character count and turns off resizing.", layout: :column do
    ~H"""
    <.text_area
      id="text-area-disabled"
      name="message"
      label="Message template"
      value="Build failed on main. Check the logs in the Tuist dashboard."
      disabled
    />
    """
  end
end
