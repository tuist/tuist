defmodule Atlas.OAuth.NoCache do
  @moduledoc """
  Disables Boruta's replica-local credential and client caches.

  A revocation or client update must be visible on the next request regardless
  of which instance handles it. Boruta's Ecto adapters fall back to PostgreSQL
  on a cache miss; writes/deletes remain no-ops with the expected return shape.
  """

  def get(_key), do: nil
  def put(_key, _value, _opts \\ []), do: :ok
  def delete(_key), do: :ok
end
