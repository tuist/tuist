defmodule Tuist.Native.S3AccessKeyPair do
  @moduledoc ~S"""
  It represents the access key pair used to authenticate with S3.
  """
  defstruct [:access_key, :secret_key]
end
