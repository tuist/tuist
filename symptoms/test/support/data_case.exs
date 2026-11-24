defmodule Symptoms.DataCase do
  @moduledoc """
  Database tests: tagged `:db`, each in a sandboxed transaction. Delay draws
  never fire (`random` returns 0.99) so decisions are deterministic.
  """
  use ExUnit.CaseTemplate

  alias Ecto.Adapters.SQL.Sandbox

  using do
    quote do
      import Ecto.Query
      import Symptoms.DataCase

      alias Symptoms.Repo

      @moduletag :db
    end
  end

  setup tags do
    pid = Sandbox.start_owner!(Symptoms.Repo, shared: not tags[:async])
    previous = Application.get_env(:symptoms, :policy)
    Application.put_env(:symptoms, :policy, random: {__MODULE__, :never_delay, []})

    on_exit(fn ->
      Application.put_env(:symptoms, :policy, previous || [])
      Sandbox.stop_owner(pid)
    end)

    :ok
  end

  def never_delay, do: 0.99
end
