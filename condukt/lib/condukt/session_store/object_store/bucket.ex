defmodule Condukt.SessionStore.ObjectStore.Bucket do
  @moduledoc """
  The object storage `Condukt.SessionStore.ObjectStore` writes to.

  A bucket is passed as `{module, config}`. Condukt ships
  `Condukt.SessionStore.ObjectStore.S3`, for S3 and services compatible with
  it such as Tigris, R2, and MinIO, and `Condukt.SessionStore.ObjectStore.Memory`
  for tests.

  The store only ever creates objects, and relies on a create failing when the
  key already exists: that is how a writer that lost its session finds out.
  A bucket must therefore make `create/3` atomic, as S3 does for a `PutObject`
  with `If-None-Match: *`, and `list/3` must see every object whose create
  has returned.
  """

  @doc "Creates the object, or returns `{:error, :exists}` when the key already has one."
  @callback create(term(), key :: String.t(), body :: binary()) :: :ok | {:error, :exists} | {:error, term()}

  @callback get(term(), key :: String.t()) :: {:ok, binary()} | :not_found | {:error, term()}

  @doc "Every key under `prefix` that sorts after `start_after`, in ascending order."
  @callback list(term(), prefix :: String.t(), start_after :: String.t() | nil) ::
              {:ok, [String.t()]} | {:error, term()}

  @doc "Deletes the object, succeeding when there is none."
  @callback delete(term(), key :: String.t()) :: :ok | {:error, term()}
end
