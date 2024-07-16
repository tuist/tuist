defmodule Tuist.Native.S3DeleteAllObjectsOptions do
  @moduledoc ~S"""
  It represents the options that can be passed to the `s3_delete_all_objects` function.
  """
  defstruct [:bucket_name, :region, :prefix, :credentials]
end
