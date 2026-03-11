defmodule TuistWeb.Storybook.Popover do
  @moduledoc false
  use PhoenixStorybook.Story, :component

  alias Noora.Button
  alias Noora.Icon
  alias Noora.TextInput

  def function, do: &Noora.Popover.popover/1

  def imports,
    do: []

  def variations do
    [
      %Variation{
        id: :default,
        description: "Simple popover with basic content",
        slots: [
          """
          <:trigger :let={attrs}>
            <button {attrs} style="padding: 8px 16px;">
              Click me
            </button>
          </:trigger>
          <div style="padding: 16px;">
            <h3 style="margin: 0 0 8px 0; color: var(--noora-surface-label-primary);">Popover Title</h3>
            <p style="margin: 0; color: var(--noora-surface-label-secondary);">This is the content inside the popover.</p>
          </div>
          """
        ]
      }
    ]
  end
end
