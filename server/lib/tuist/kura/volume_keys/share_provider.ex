defmodule Tuist.Kura.VolumeKeys.ShareProvider do
  @moduledoc """
  Wraps and unwraps one share of a Kura tenant key.

  A share is stored as a map whose `"provider"` names the implementation that
  produced it; every other field belongs to that provider. `aad` binds the
  ciphertext to the tenant, key version, and share position, so a share cannot
  be moved to another tenant or slot.
  """

  @callback provider() :: String.t()
  @callback wrap(plaintext :: binary(), aad :: binary()) :: {:ok, map()} | {:error, term()}
  @callback unwrap(share :: map(), aad :: binary()) :: {:ok, binary()} | {:error, term()}
end
