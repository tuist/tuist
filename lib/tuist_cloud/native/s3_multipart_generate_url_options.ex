defmodule TuistCloud.Native.S3MultipartGenerateURLOptions do
  @moduledoc ~S"""
  It represents the options that can be passed to the `s3_multipart_generate_url` function.
  """
  defstruct [
    :expires_in,
    :credentials,
    :object_key,
    :region,
    :bucket_name,
    :part_number,
    :upload_id
  ]
end
