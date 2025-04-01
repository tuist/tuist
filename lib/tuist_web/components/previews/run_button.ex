defmodule TuistWeb.Previews.RunButton do
  @moduledoc """
  Component for rendering a button to run a preview.
  """
  use TuistWeb, :live_component
  use TuistWeb.Noora

  attr :preview, :map, required: true
  attr :user_agent, :map, required: true

  def run_button(assigns) do
    ~H"""
    <% href =
      case {@user_agent |> Map.get(:os), @preview.type} do
        {"iOS", :ipa} ->
          {"itms-services" |> String.to_atom(),
           "//?action=download-manifest&url=#{url(~p"/#{@preview.project.account.name}/#{@preview.project.name}/previews/#{@preview.id}/manifest.plist")}"}

        {"iOS", _} ->
          nil

        _ ->
          {:tuist,
           "open-preview?server_url=#{TuistWeb.Endpoint.url()}&preview_id=#{@preview.id}&full_handle=#{@preview.project.account.name}/#{@preview.project.name}"}
      end %>
    <%= if not is_nil(href) do %>
      <.button icon_only variant="secondary" size="small" href={href}>
        <.player_play />
      </.button>
    <% end %>
    """
  end
end
