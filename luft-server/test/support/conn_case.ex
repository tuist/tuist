defmodule LuftServerWeb.ConnCase do
  @moduledoc false
  use ExUnit.CaseTemplate
  alias Ecto.Adapters.SQL.Sandbox

  using do
    quote do
      import Phoenix.ConnTest
      import Plug.Conn

      @endpoint LuftServerWeb.Endpoint
    end
  end

  setup tags do
    pid = Sandbox.start_owner!(LuftServer.Repo, shared: not tags[:async])
    on_exit(fn -> Sandbox.stop_owner(pid) end)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end
