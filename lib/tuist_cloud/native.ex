defmodule TuistCloud.Native do
  @moduledoc """
  This module is an interface to the native code (Rust-based) that Tuist Cloud uses.
  """
  use Rustler, otp_app: :tuist_cloud, crate: "tuistcloud_native"

  def license(), do: :erlang.nif_error(:nif_not_loaded)
  def s3_download_presigned_url(_options), do: :erlang.nif_error(:nif_not_loaded)
  def s3_exists(_options), do: :erlang.nif_error(:nif_not_loaded)
  def s3_multipart_start(_options), do: :erlang.nif_error(:nif_not_loaded)
  def s3_multipart_generate_url(_options), do: :erlang.nif_error(:nif_not_loaded)
  def s3_multipart_complete_upload(_options), do: :erlang.nif_error(:nif_not_loaded)
  def s3_size(_options), do: :erlang.nif_error(:nif_not_loaded)
  def s3_delete_all_objects(_options), do: :erlang.nif_error(:nif_not_loaded)
  def s3_get_object_as_string(_options), do: :erlang.nif_error(:nif_not_loaded)
end
