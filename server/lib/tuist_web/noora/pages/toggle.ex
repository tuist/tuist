defmodule TuistWeb.Noora.Pages.Toggle do
  @moduledoc false
  use TuistWeb.Noora.Page,
    title: "Toggle",
    description: "Switches a setting on or off with immediate effect.",
    components: [{Noora.Toggle, :toggle}],
    guidelines: [
      "Use a toggle for a setting that applies as soon as it changes, such as enabling Slack reports. React to it with `phx-click` or with a `data-on-checked-change` event, which receives the new `checked` value.",
      "Always pass an `id`. The toggle derives the id of its label from it and fails to render without one.",
      "The toggle follows `checked` when the server changes it. Between changes it keeps the state people set in the browser.",
      "Pass `field` or `name` to submit the toggle with a form. It submits true when on and false when off.",
      "`description` only renders together with `label`. Without a `label`, place the setting's name next to the toggle yourself.",
      "Name the setting in the label, such as Enable Single Sign-On, rather than describing the on and off states."
    ]

  example "States" do
    ~H"""
    <.toggle id="toggle-off" label="Slack reports" />
    <.toggle id="toggle-on" label="Slack reports" checked />
    """
  end

  example "Sizes", description: "Large suits a setting that stands on its own, such as the main switch of a page." do
    ~H"""
    <.toggle id="toggle-size-medium" label="Medium" checked />
    <.toggle id="toggle-size-large" label="Large" size="large" checked />
    """
  end

  example "With description", description: "A second line explains what the setting does.", layout: :column do
    ~H"""
    <.toggle
      id="toggle-description-default-branch"
      label="Default branch"
      description="Jobs on each repository's default branch save their changes."
      checked
    />
    <.toggle
      id="toggle-description-pull-requests"
      label="Pull requests"
      description="Jobs on pull requests save their changes too."
    />
    """
  end

  example "Without label", description: "The control on its own, for rows that already show the setting's name." do
    ~H"""
    <.toggle id="toggle-standalone-off" />
    <.toggle id="toggle-standalone-on" checked />
    """
  end

  example "Disabled" do
    ~H"""
    <.toggle id="toggle-disabled-off" label="Enforce Single Sign-On" disabled />
    <.toggle id="toggle-disabled-on" label="Enforce Single Sign-On" checked disabled />
    """
  end
end
