defmodule Condukt.SessionStore.Memory.Table do
  @moduledoc false
  # Owns the table `Condukt.SessionStore.Memory` writes into.
  #
  # An ETS table belongs to the process that created it and dies with it. When
  # the table was created lazily by whichever caller happened to arrive first,
  # its lifetime was that caller's: an unrelated session exiting took every
  # stored snapshot with it, at a moment nothing in the system could predict.
  # Creating it here ties it to the supervision tree instead, which is the only
  # process whose lifetime matches the table's intended one.
  #
  # Owning it from a supervised process also removes the cluster-wide
  # `:global.trans` the old lazy path needed to make creation safe under
  # concurrency. There is one creator now, so there is no race to arbitrate.

  use GenServer

  @table Condukt.SessionStore.Memory

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "The table's name, which is also its identifier."
  def name, do: @table

  @doc """
  The table, raising when the application that owns it is not running.

  A missing table used to mean "create one"; it now means the caller reached
  the store before `:condukt` started, which is worth saying plainly rather
  than papering over with a table nobody owns.
  """
  def table! do
    case :ets.whereis(@table) do
      :undefined ->
        raise "the :condukt application must be started before using Condukt.SessionStore.Memory"

      tid ->
        tid
    end
  end

  @impl GenServer
  def init(_opts) do
    :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    {:ok, %{}}
  end
end
