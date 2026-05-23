defmodule SlackWeb.CoreComponents do
  @moduledoc """
  Minimal HTML helpers used across the Slack application.

  The visual parts of the UI rely on the Noora component library;
  this module just provides a small flash helper reused by the layouts.
  """
  use Phoenix.Component
  use Noora

  attr :flash, :map, default: %{}

  def flash_group(assigns) do
    assigns =
      assigns
      |> assign(:info, Phoenix.Flash.get(assigns.flash, :info))
      |> assign(:error, Phoenix.Flash.get(assigns.flash, :error))

    ~H"""
    <div
      :if={@info || @error}
      id="flash-group"
      phx-click={Phoenix.LiveView.JS.hide(to: "#flash-group")}
      role="alert"
    >
      <.alert
        :if={@info}
        id="flash-info"
        type="primary"
        status="success"
        size="small"
        title={@info}
      />
      <.alert
        :if={@error}
        id="flash-error"
        type="primary"
        status="error"
        size="small"
        title={@error}
      />
    </div>
    """
  end
end
