defmodule LuftServerWeb do
  @moduledoc false

  def router do
    quote do
      use Phoenix.Router, helpers: false

      import Phoenix.Controller
      import Plug.Conn
    end
  end

  def controller do
    quote do
      use Phoenix.Controller, formats: [:json]

      import Plug.Conn
    end
  end

  defmacro __using__(which) when is_atom(which), do: apply(__MODULE__, which, [])
end
