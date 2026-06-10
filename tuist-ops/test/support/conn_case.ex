defmodule TuistOpsWeb.ConnCase do
  @moduledoc """
  Test case for tests that exercise controllers / plugs through
  the Phoenix endpoint pipeline. Sandboxes `TuistOps.Repo` per
  test (same isolation as DataCase) and gives every test a
  fresh `%Plug.Conn{}` via `Phoenix.ConnTest.build_conn/0`.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import Plug.Conn
      import Phoenix.ConnTest

      alias TuistOpsWeb.Router.Helpers, as: Routes

      @endpoint TuistOpsWeb.Endpoint
    end
  end

  setup tags do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(TuistOps.Repo, shared: not tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end
