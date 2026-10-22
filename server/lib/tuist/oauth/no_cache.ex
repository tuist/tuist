defmodule Tuist.OAuth.NoCache do
  @moduledoc """
  Boruta entity-cache backend that always reads authoritative database state.

  Boruta's default replicated cache takes cluster-wide locks on writes and can
  retain revoked grants during partitions. Its stores require only get, put and
  delete; keeping those operations inert avoids both node affinity and replication.
  This does not disable the independent immutable bcrypt-proof cache.
  """

  def get(_key), do: nil
  def put(_key, _value, _opts \\ []), do: :ok
  def delete(_key), do: :ok
end
