defmodule TuistWeb.AppCommandEventComponents do
  @moduledoc """
  Components for presenting command events
  """

  use Phoenix.Component
  import TuistWeb.AppComponents
  import TuistWeb.Components.IconComponents
  use Gettext, backend: TuistWeb.Gettext

  attr(:command_event, :map, required: true)

  def command_event_ran_by_badge(assigns) do
    ~H"""
    <%= cond do %>
      <% not is_nil(@command_event.user) -> %>
        <.legacy_badge title={@command_event.user.account.name} kind={:brand}>
          <:icon><.user_icon /></:icon>
        </.legacy_badge>
      <% @command_event.is_ci -> %>
        <.legacy_badge title={gettext("CI")} kind={:neutral}>
          <:icon><.settings_icon /></:icon>
        </.legacy_badge>
      <% true -> %>
        <.legacy_badge title={gettext("Unknown")} kind={:warning}>
          <:icon><.user_icon /></:icon>
        </.legacy_badge>
    <% end %>
    """
  end

  attr(:preview, :map, required: true)

  def preview_ran_by_badge(assigns) do
    ~H"""
    <%= if is_nil(@preview.ran_by_account) do %>
      <.command_event_ran_by_badge command_event={@preview.command_event} />
    <% else %>
      <%= if is_nil(@preview.ran_by_account.user_id) do %>
        <.legacy_badge title={gettext("CI")} kind={:neutral}>
          <:icon><.settings_icon /></:icon>
        </.legacy_badge>
      <% else %>
        <.legacy_badge title={@preview.ran_by_account.name} kind={:brand}>
          <:icon><.user_icon /></:icon>
        </.legacy_badge>
      <% end %>
    <% end %>
    """
  end

  def command_event_status_badge(assigns) do
    ~H"""
    <.legacy_badge
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
    <.legacy_badge
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
