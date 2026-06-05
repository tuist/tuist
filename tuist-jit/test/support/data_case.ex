defmodule TuistJit.DataCase do
  @moduledoc """
  Test case for tests that touch the database. Sandboxes the
  TuistJit.Repo so each test runs in its own transaction.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      alias TuistJit.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import TuistJit.DataCase
    end
  end

  setup tags do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(TuistJit.Repo, shared: not tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
    :ok
  end
end
