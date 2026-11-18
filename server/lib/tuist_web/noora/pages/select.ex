defmodule TuistWeb.Noora.Pages.Select do
  @moduledoc false
  use TuistWeb.Noora.Page,
    title: "Select",
    description: "Lets people choose one option from a list in a dropdown.",
    components: [{Noora.Select, :select}],
    guidelines: [
      "`label` is the text in the trigger, shown until an option is chosen. Write it as a prompt, such as Select a country, and title the field with a label component above the select.",
      "Pass `name` to submit the choice with a form. The select renders a hidden native select with that name.",
      "Use `on_value_change` to react to a choice right away. The event receives the chosen values as a list under `value`.",
      "Give every `:item` both a `value` and a `label`. The menu and the trigger show the `label`, and the form submits the `value`.",
      "The list of items and the choice live in the browser once the select mounts. When the items change on the server, change the select's `id` so it remounts."
    ]

  example "Default", description: "`label` shows in the trigger until an option is chosen.", layout: :column do
    ~H"""
    <.select id="select-default" label="Select build system" name="build_system">
      <:item value="xcode" label="Xcode" />
      <:item value="gradle" label="Gradle" />
      <:item value="bazel" label="Bazel" />
      <:item value="mix" label="Mix (Elixir)" />
      <:item value="cargo" label="Cargo (Rust)" />
    </.select>
    """
  end

  example "Selected value", description: "With `value`, the trigger shows the matching item's label.", layout: :column do
    ~H"""
    <.select id="select-selected" label="Select platforms" name="platforms" value="all">
      <:item value="all" label="macOS and Linux" />
      <:item value="macos" label="macOS" />
      <:item value="linux" label="Linux" />
    </.select>
    """
  end

  example "With icons",
    description:
      "An `icon` on each item shows next to its label in the menu, and in the trigger for the item matching `value`.",
    layout: :column do
    ~H"""
    <.select id="select-icons" label="Select organization" name="account_id" value="tuist">
      <:item value="tuist" label="tuist" icon="building" />
      <:item value="acme-mobile" label="acme-mobile" icon="building" />
      <:item value="marek" label="marek" icon="user" />
    </.select>
    """
  end

  example "With hint", layout: :column do
    ~H"""
    <.select
      id="select-hint"
      label="Select a region"
      name="region"
      hint="Cache artifacts are stored in this region."
    >
      <:item value="eu-central" label="Europe (Frankfurt)" />
      <:item value="us-east" label="US East (Virginia)" />
      <:item value="ap-southeast" label="Asia Pacific (Singapore)" />
    </.select>
    """
  end

  example "Disabled", layout: :column do
    ~H"""
    <.select
      id="select-disabled"
      label="Select build system"
      name="build_system"
      value="xcode"
      disabled
    >
      <:item value="xcode" label="Xcode" />
      <:item value="gradle" label="Gradle" />
    </.select>
    """
  end
end
