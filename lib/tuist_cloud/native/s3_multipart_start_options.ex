defmodule TuistCloud.Native.S3MultipartStartOptions do
  @moduledoc ~S"""
  It represents the options that can be passed to the `s3_multipart_start` function.
  """
  defstruct [:credentials, :object_key, :region, :bucket_name]
end
