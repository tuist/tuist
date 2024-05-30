defmodule TuistCloud.Native.S3SizeOptions do
  @moduledoc ~S"""
  It represents the options that can be passed to the `s3_size` function.
  """
  defstruct [:bucket_name, :region, :object_key, :credentials]
end
