defmodule TuistCloud.Native.S3DownloadPresignedURLOptions do
  @moduledoc ~S"""
  It represents the options that can be passed to the `s3_download_presigned_url` function.
  """
  defstruct [:expires_in, :credentials, :object_key, :region, :bucket_name]
end
