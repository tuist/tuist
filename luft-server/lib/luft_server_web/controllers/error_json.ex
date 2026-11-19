defmodule LuftServerWeb.ErrorJSON do
  @moduledoc false
  def render(template, _assigns),
    do: %{error: Phoenix.Controller.status_message_from_template(template)}
end
