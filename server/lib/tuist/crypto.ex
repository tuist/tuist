defmodule Tuist.Crypto do
  @moduledoc ~S"""
  A module to deal with cryptographic methods.
  """
  def hash_init(algorithm) do
    :crypto.hash_init(algorithm)
  end

  def hash_update(data, new_data) do
    :crypto.hash_update(data, new_data)
  end

  def hash_final(data) do
    :crypto.hash_final(data)
  end

  def decode(data) do
    :base64.decode(data)
  end
end
