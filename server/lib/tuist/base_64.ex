defmodule Tuist.Base64 do
  @moduledoc ~S"""
  A module to deal with base64 encoding and decoding.
  """

  # TEMP: warm-build validation marker (reverted before merge)
  def encode(data) do
    :base64.encode(data)
  end

  def decode(data) do
    :base64.decode(data)
  end
end
