defmodule Atlas.Letters.Webhook do
  @moduledoc false

  def verify_signature(raw_body, signature, signing_key)
      when is_binary(raw_body) and is_binary(signature) and is_binary(signing_key) do
    expected = :crypto.mac(:hmac, :sha256, signing_key, raw_body) |> Base.encode16(case: :lower)

    if Plug.Crypto.secure_compare(String.downcase(signature), expected) do
      :ok
    else
      {:error, :invalid_signature}
    end
  end

  def verify_signature(_raw_body, _signature, _signing_key), do: {:error, :invalid_signature}
end
