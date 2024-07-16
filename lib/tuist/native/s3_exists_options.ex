defmodule Tuist.Native.S3ExistsOptions do
  @moduledoc ~S"""
  It represents the options that can be passed to the `s3_exists` function.
  """
  defstruct [:credentials, :object_key, :region, :bucket_name]
end
