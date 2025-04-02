defmodule TuistWeb.Runs.RanByBadge do
  @moduledoc """
  A component used to render a badge indicating who executed the run.
  """
  use Phoenix.Component
  use TuistWeb.Noora

  attr :run, :map, required: true

  def run_ran_by_badge_cell(assigns) do
    ~H"""
    <%= if @run.is_ci do %>
      <.badge_cell label="CI" icon="settings" color="information" style="light-fill" />
    <% else %>
      <.badge_cell label={@run.user.account.name} icon="user" color="primary" style="light-fill" />
    <% end %>
    """
  end
end
