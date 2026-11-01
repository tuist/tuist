defmodule Tuist.Storage.S3Target do
  @moduledoc "An explicitly routed S3 store, independent of an account's default storage."
  @derive {Inspect, only: [:id, :bucket]}
  @enforce_keys [:id, :config, :bucket]
  defstruct [:id, :config, :bucket]
end
