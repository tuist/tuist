defmodule TuistWeb.Noora.Pages.Tag do
  @moduledoc false
  use TuistWeb.Noora.Page,
    title: "Tag",
    description: "Labels an item with a short attribute, such as a platform, category, or event type.",
    components: [{Noora.Tag, :tag}, {Noora.Tag, :input_tag}],
    guidelines: [
      "Use tags for neutral attributes such as platforms, categories, and event types. For states and outcomes, use a badge or a status badge.",
      "Add an `icon` when it makes the value faster to recognize, such as a device icon for a platform.",
      "A dismissible tag sends `on_dismiss` to the server with `dismiss_value` as the `data` parameter. The tag does not hide itself, so remove it from your assigns in the handler.",
      "Use `input_tag` for values a person typed into a field, such as email addresses in an invite form. It has no icon and uses the parts the tags input hook reads."
    ]

  example "Default" do
    ~H"""
    <.tag label="build.completed" />
    <.tag label="test_run.completed" />
    <.tag label="preview.uploaded" />
    """
  end

  example "With icon", description: "An icon before the label makes the value easier to scan." do
    ~H"""
    <.tag label="iOS" icon="device_mobile" />
    <.tag label="macOS" icon="device_laptop" />
    <.tag label="main" icon="git_branch" />
    """
  end

  example "Dismissible", description: "A dismiss button sends `on_dismiss` with the tag's `dismiss_value`." do
    ~H"""
    <.tag label="Status: Failed" dismissible on_dismiss="remove-filter" dismiss_value="status" />
    <.tag
      label="iOS"
      icon="device_mobile"
      dismissible
      on_dismiss="remove-filter"
      dismiss_value="platform"
    />
    """
  end

  example "Disabled", description: "Mutes the tag and disables its dismiss button." do
    ~H"""
    <.tag label="Archived" disabled />
    <.tag label="watchOS" icon="device_watch" disabled />
    <.tag
      label="Status: Failed"
      dismissible
      on_dismiss="remove-filter"
      dismiss_value="status"
      disabled
    />
    """
  end

  example "Input tag", description: "For values entered into a field, with an optional dismiss button." do
    ~H"""
    <.input_tag
      label="marek@tuist.dev"
      dismissible
      on_dismiss="remove-email"
      dismiss_value="marek@tuist.dev"
    />
    <.input_tag
      label="pedro@tuist.dev"
      dismissible
      on_dismiss="remove-email"
      dismiss_value="pedro@tuist.dev"
    />
    <.input_tag label="chris@tuist.dev" />
    """
  end
end
