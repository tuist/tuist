defmodule Tuist.Native.S3GetObjectOptions do
  @moduledoc ~S"""
  It represents the options that can be passed to the `s3_get_object_as_string` function.
  """
  defstruct [:credentials, :object_key, :region, :bucket_name]
end
