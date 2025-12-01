defmodule TuistTestSupport.Cases.DataCase do
  @moduledoc """
  This module defines the setup for tests requiring
  access to the application's data layer.

  You may define functions here to be used as helpers in
  your tests.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use TuistTestSupport.Cases.DataCase, async: true`, although
  this option is not recommended for other databases.
  """
  use ExUnit.CaseTemplate

  alias Ecto.Adapters.SQL.Sandbox

  require File

  using do
    quote do
      use Oban.Testing, repo: Tuist.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import Tuist.Ecto.Utils, only: [errors_on: 1]
      import TuistTestSupport.Cases.DataCase
      import TuistTestSupport.Utilities

      alias Tuist.Repo
    end
  end

  setup tags do
    TuistTestSupport.Cases.DataCase.setup_sandbox(tags)

    on_exit(fn ->
      TuistTestSupport.Utilities.truncate_clickhouse_tables()
    end)

    :ok
  end

  @doc """
  Sets up the sandbox based on the test tags.
  """
  def setup_sandbox(tags) do
    pid = Sandbox.start_owner!(Tuist.Repo, shared: not tags[:async])
    on_exit(fn -> Sandbox.stop_owner(pid) end)
  end
end
