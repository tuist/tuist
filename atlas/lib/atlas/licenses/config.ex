defmodule Atlas.Licenses.Config do
  @moduledoc """
  Runtime configuration for licenses.

  Exists as a seam so code and tests read license settings through a function
  rather than reaching into the application environment directly.
  """

  @doc """
  The Base64-encoded Ed25519 private key used to sign air-gapped license files.

  Returns `nil` when signing is not configured, which is the normal state for
  environments that only serve online validation.
  """
  def signing_private_key do
    case Application.get_env(:atlas, :licenses, [])[:signing_private_key] do
      key when is_binary(key) and key != "" -> key
      _key -> nil
    end
  end
end
