defmodule TuistWeb.Previews.RunButton do
  @moduledoc """
  Component for rendering a button to run a preview.
  """
  use TuistWeb, :live_component
  use Noora

  attr :preview, :map, required: true
  attr :user_agent, :map, required: true
  attr :rest, :global

  def run_button(assigns) do
    ~H"""
    <% href =
      case {@user_agent |> Map.get(:os),
            Enum.map(@preview.app_builds, & &1.type) |> Enum.member?(:ipa)} do
        {"iOS", true} ->
          {"itms-services" |> String.to_atom(),
           "//?action=download-manifest&url=#{url(~p"/#{@preview.project.account.name}/#{@preview.project.name}/previews/#{@preview.id}/manifest.plist")}"}

        {"iOS", _} ->
          nil

        _ ->
          {:tuist,
           "open-preview?server_url=#{TuistWeb.Endpoint.url()}&preview_id=#{@preview.id}&full_handle=#{@preview.project.account.name}/#{@preview.project.name}"}
      end %>
    <%= if not is_nil(href) do %>
      <.button icon_only variant="secondary" size="small" href={href} {@rest}>
        <.player_play />
      </.button>
    <% end %>
    """
  end
end
