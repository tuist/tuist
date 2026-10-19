defmodule Tuist.OAuth.AuthoritativeCache do
  @moduledoc """
  Boruta compatibility backend with authoritative reads and legacy invalidations.

  Reads always fall through to the upstream Ecto adapters, and fills are ignored.
  Invalidations still reach Boruta's replicated cache because older replicas and
  rolled-back binaries may read entries already stored there. Invalidation errors
  propagate rather than acknowledging a stale grant. Because fills no longer fail
  before revocation, an invalidation failure can consume a code or refresh token
  after the database commit without delivering its replacement; re-authorization
  may be necessary. This release does not make the upstream sequence atomic.

  Deploy this compatibility backend fleet-wide before separately removing the
  legacy invalidations or changing cluster membership. This phase still depends
  on Boruta's existing replicated invalidation and membership behavior; it does
  not claim to solve legacy partitions or eliminate cluster-wide locks.

  Immutable bcrypt proofs, bounded authentication subjects and issued Guardian
  JWT revocation semantics are unchanged.
  """

  def get(_key), do: nil
  def put(_key, _value, _opts \\ []), do: :ok
  def delete(key), do: Boruta.Cache.delete(key)
end
