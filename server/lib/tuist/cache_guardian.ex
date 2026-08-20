defmodule Tuist.CacheGuardian do
  @moduledoc """
  Signs the short-lived tokens cache nodes authorize from.

  Separate from `Tuist.Guardian` because the two keys answer to different
  holders. A cache node is given the public half of this keypair so it can read
  a token where the request lands instead of asking here, which means every node
  can read every cache token and none of them can mint one. `Tuist.Guardian`
  signs with a symmetric key that also signs API credentials, so a node holding
  it could mint those; that key never leaves the server.

  Without a keypair configured, cache tokens are signed by `Tuist.Guardian` as
  before and nodes answer them through introspection.
  """

  use Guardian, otp_app: :tuist

  # Written out rather than aliased: `Guardian` in this module is the library
  # this one is built on, not the sibling it delegates to.
  defdelegate subject_for_token(resource, claims), to: Tuist.Guardian

  # Nothing signed here is ever an API credential. `Tuist.Guardian` refuses the
  # same token type for the same reason.
  def resource_from_claims(_claims), do: {:error, :invalid_token_type}

  @doc """
  Whether a dedicated cache-token keypair is configured.
  """
  def configured? do
    :tuist
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:secret_key)
    |> then(&(not is_nil(&1)))
  end
end
