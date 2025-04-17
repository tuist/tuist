defmodule TuistWeb.HeadlessComponents do
  @moduledoc """
  A set of headless components
  """
  use Phoenix.Component

  alias Phoenix.LiveView.JS

  @doc ~S"""
  This component represents a dropdown that is controlled by a button.
  Note that the :activator slot should set the provided attributes to the button element.
  <:activator :let={attrs}>
    <button {attrs}>
    </button>
  </:activator>
  """
  attr(:class, :string, default: "")
  attr(:dropdown_id, :string, required: true)
  slot(:activator, required: true)
  slot(:inner_block, required: true)

  def headless_dropdown(assigns) do
    ~H"""
    <div class={"headless_dropdown #{@class}"}>
      {render_slot(
        @activator,
        %{
          "aria-expanded" => "false",
          "phx-key" => "Escape",
          "phx-click" => JS.toggle(to: "##{@dropdown_id}"),
          "phx-window-keydown" => JS.hide(to: "##{@dropdown_id}")
        }
      )}
      <div id={@dropdown_id} hidden phx-click-away={JS.hide(to: "##{@dropdown_id}")}>
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end
end
