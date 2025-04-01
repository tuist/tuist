defmodule TuistWeb.Previews.RanByBadge do
  @moduledoc """
  A component used to render a badge indicating who ran the preview.
  """
  use Phoenix.Component
  use TuistWeb.Noora

  attr :preview, :map, required: true

  def ran_by_badge_cell(assigns) do
    ~H"""
    <%= if (@preview.command_event && @preview.command_event.is_ci) || is_nil(@preview.ran_by_account) || is_nil(@preview.ran_by_account.user_id) do %>
      <.badge_cell label="CI" icon="settings" color="information" style="light-fill" />
    <% else %>
      <.badge_cell
        label={@preview.ran_by_account.name}
        icon="user"
        color="primary"
        style="light-fill"
      />
    <% end %>
    """
  end
end
