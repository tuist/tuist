defmodule TuistCloud.Native.S3MultipartCompleteUploadOptions do
  @moduledoc """
  It represents the options that can be passed to the `s3_multipart_complete_upload` function.
  """
  defstruct [:bucket_name, :credentials, :object_key, :region, :upload_id, :parts]
end
