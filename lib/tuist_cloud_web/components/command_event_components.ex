defmodule TuistCloudWeb.CommandEventComponents do
  @moduledoc """
  Components for presenting command events
  """

  use Phoenix.Component
  import TuistCloudWeb.CoreComponents
  import TuistCloudWeb.Components.Icons
  import TuistCloudWeb.Gettext

  attr(:command_event, :map, required: true)

  def command_event_ran_by_badge(assigns) do
    ~H"""
    <%= if @command_event.is_ci do %>
      <.badge title={gettext("CI")} kind={:neutral}>
        <:icon><.settings /></:icon>
      </.badge>
    <% else %>
      <.badge title={gettext("Unknown")} kind={:warning}>
        <:icon><.user /></:icon>
      </.badge>
    <% end %>
    """
  end

  def command_event_status_badge(assigns) do
    ~H"""
    <.badge
      title={Atom.to_string(@command_event.status)}
      kind={
        case @command_event.status do
          :success -> :success
          :failure -> :error
        end
      }
    />
    """
  end
end
