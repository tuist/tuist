defmodule AtlasWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use AtlasWeb, :html
  use Noora

  import AtlasWeb.CoreComponents, only: []
  import AtlasWeb.SearchPalette, only: [search_palette: 1]

  alias Phoenix.LiveView.JS

  embed_templates "layouts/*"

  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.alert
        :if={Phoenix.Flash.get(@flash, :info)}
        id="flash-info"
        type="secondary"
        status="success"
        size="small"
        title={Phoenix.Flash.get(@flash, :info)}
        dismissible
      />
      <.alert
        :if={Phoenix.Flash.get(@flash, :error)}
        id="flash-error"
        type="secondary"
        status="error"
        size="small"
        title={Phoenix.Flash.get(@flash, :error)}
        dismissible
      />

      <.alert
        id="client-error"
        type="secondary"
        status="warning"
        size="small"
        title={gettext("Connection lost. Attempting to reconnect...")}
        phx-disconnected={
          JS.show(to: ".phx-client-error #client-error") |> JS.remove_attribute("hidden")
        }
        phx-connected={JS.hide(to: "#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      />

      <.alert
        id="server-error"
        type="secondary"
        status="error"
        size="small"
        title={gettext("Something went wrong. Attempting to reconnect...")}
        phx-disconnected={
          JS.show(to: ".phx-server-error #server-error") |> JS.remove_attribute("hidden")
        }
        phx-connected={JS.hide(to: "#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      />
    </div>
    """
  end
end
