defmodule TuistCloud.Native do
  @moduledoc """
  This module is an interface to the native code (Rust-based) that Tuist Cloud uses.
  """
  use Rustler, otp_app: :tuist_cloud, crate: "tuistcloud_native"

  # When your NIF is loaded, it will override this function.
  def license(), do: :erlang.nif_error(:nif_not_loaded)
end
