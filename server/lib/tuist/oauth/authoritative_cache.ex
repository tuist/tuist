defmodule Tuist.OAuth.AuthoritativeCache do
  @moduledoc """
  Boruta backend with authoritative reads and no replicated entity operations.

  Reads always fall through to the upstream Ecto adapters. Fills and invalidations
  are no-ops, so OAuth entity mutations do not wait for replicated cache RPC/locks
  after committing to PostgreSQL. Boruta still starts its cache and membership
  processes; this backend does not remove their startup or lifecycle behavior.

  Upgrade every OAuth consumer, including background jobs, to the authoritative-
  reading compatibility release (#14040) before deploying this version. It can
  overlap and roll back to that release, but not to cache-reading binaries: their
  retained entries can be stale after mutations here. To roll back further, first
  stop every no-invalidation consumer, then clear or replace every retained cache
  participant and prevent old participants from rejoining before readers start.

  Upstream code redemption and refresh rotation are not made atomic. Immutable
  bcrypt proofs, bounded authentication subjects and already-issued Guardian JWT
  revocation semantics are unchanged.
  """

  def get(_key), do: nil
  def put(_key, _value, _opts \\ []), do: :ok
  def delete(_key), do: :ok
end
