defmodule TuistWeb.Noora.Pages.Checkbox do
  @moduledoc false
  use TuistWeb.Noora.Page,
    title: "Checkbox",
    description: "Lets people turn an option on or off as part of a form they confirm separately.",
    components: [{Noora.Checkbox, :checkbox}],
    guidelines: [
      "Write the `label` as the option itself, such as Keep me logged in, so checking the box reads as agreeing to it.",
      "Write a label that acknowledges something as a full sentence, such as I agree to the Terms of Service.",
      "Use `description` for the consequence of the option rather than restating the label.",
      "Use `indeterminate` on a checkbox that controls a group when only some of the group is checked. It's a visual state, not a third value: set it from the group, and clear it once the group is all checked or all unchecked.",
      "Wrap related checkboxes in a `fieldset` with a `legend` naming the group, such as Notifications.",
      "Pass `field` to take the id, name, and value from a form field. Add `multiple` when several checkboxes share one field, so the name ends in `[]`.",
      "For a setting that applies as soon as it changes, use a toggle instead. A checkbox suits choices confirmed with a separate action, such as a submit button."
    ]

  example "Default" do
    ~H"""
    <.checkbox id="checkbox-unchecked" label="Unchecked" />
    <.checkbox id="checkbox-checked" label="Checked" checked />
    """
  end

  example "Indeterminate" do
    ~H"""
    <.checkbox id="checkbox-indeterminate" label="Indeterminate" indeterminate />
    """
  end

  example "Disabled", layout: :list do
    ~H"""
    <.checkbox id="checkbox-disabled" label="Disabled" disabled />
    <.checkbox id="checkbox-disabled-checked" label="Disabled checked" checked disabled />
    <.checkbox
      id="checkbox-disabled-indeterminate"
      label="Disabled indeterminate"
      indeterminate
      disabled
    />
    """
  end

  example "With description", description: "A second line explains what the option changes.", layout: :list do
    ~H"""
    <.checkbox
      id="checkbox-description-flaky"
      label="Mark flaky tests"
      description="Tests that pass and fail on the same commit are flagged in test insights."
    />
    <.checkbox
      id="checkbox-description-slack"
      label="Post build summaries to Slack"
      description="A summary is sent to the project's channel after every build on the default branch."
    />
    """
  end
end
