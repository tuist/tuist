defmodule Tuist.OAuth.NoCache do
  @moduledoc """
  Boruta entity-cache backend that always reads authoritative database state.

  Boruta's default replicated cache takes cluster-wide locks on writes and can
  retain revoked grants during partitions. Its stores require only get, put and
  delete; keeping those operations inert avoids both node affinity and replication.
  Boruta still starts its internal replicated cache and membership processes;
  this backend only bypasses entity-store operations on upgraded replicas.
  Old replicas still read their cache, so rollout requires a drained cutover
  or a preparatory invalidate-compatible release, not ordinary mixed-version
  routing. See the OAuth context's rollout contract.

  This does not disable the independent immutable bcrypt-proof cache.
  """

  def get(_key), do: nil
  def put(_key, _value, _opts \\ []), do: :ok
  def delete(_key), do: :ok
end
