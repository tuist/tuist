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
    <%= cond do %>
      <% not is_nil(@command_event.user) -> %>
        <.badge title={@command_event.user.account.name} kind={:brand}>
          <:icon><.user /></:icon>
        </.badge>
      <% @command_event.is_ci -> %>
        <.badge title={gettext("CI")} kind={:neutral}>
          <:icon><.settings /></:icon>
        </.badge>
      <% true -> %>
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

  def test_case_run_status_badge(assigns) do
    ~H"""
    <.badge
      title={Atom.to_string(@test_case_run.status)}
      kind={
        case @test_case_run.status do
          :success -> :success
          :failure -> :error
        end
      }
    />
    """
  end
end
