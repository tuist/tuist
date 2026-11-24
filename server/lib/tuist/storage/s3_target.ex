defmodule Tuist.Storage.S3Target do
  @moduledoc """
  An explicitly routed S3 store, independent of an account's default storage.

  `presign_config`, when set, is the endpoint presigned URLs carry instead of
  `config`'s: a client that reaches the store on another host than the server,
  such as a Mac through its rack site's gateway.
  """
  @derive {Inspect, only: [:id, :bucket]}
  @enforce_keys [:id, :config, :bucket]
  defstruct [:id, :config, :bucket, :presign_config]
end
