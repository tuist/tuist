defmodule Atlas.Licenses.Issuer do
  @moduledoc """
  Issues online license credentials and signs files in Tuist's air-gapped license format.
  """

  alias Atlas.Licenses.Config
  alias Atlas.Licenses.License

  @certificate_header "-----BEGIN LICENSE FILE-----"
  @certificate_footer "-----END LICENSE FILE-----"

  def issue(%Date{} = expires_on) do
    key = "tuist_" <> Base.url_encode64(:crypto.strong_rand_bytes(24), padding: false)

    %{
      key: key,
      key_hash: key_hash(key),
      signing_key: Base.encode64(:crypto.strong_rand_bytes(32)),
      expires_on: expires_on
    }
  end

  def key_hash(key) when is_binary(key), do: :crypto.hash(:sha256, key)

  def validation_payload(nil), do: %{data: nil, meta: %{valid: false}}

  def validation_payload(%License{} = license) do
    %{
      data: license_data(license),
      meta: %{valid: active?(license)}
    }
  end

  def certificate(%License{} = license) do
    with {:ok, private_key} <- private_key() do
      encoded_data = license |> license_payload() |> JSON.encode!() |> Base.encode64()

      signature =
        :crypto.sign(:eddsa, :none, "license/" <> encoded_data, [private_key, :ed25519])

      encoded_certificate =
        %{enc: encoded_data, sig: Base.encode64(signature), alg: "base64+ed25519"}
        |> JSON.encode!()
        |> Base.encode64()
        |> wrap_lines()

      {:ok, Enum.join([@certificate_header, encoded_certificate, @certificate_footer], "\n")}
    end
  end

  def public_key do
    with {:ok, private_key} <- private_key() do
      {public_key, _private_key} = :crypto.generate_key(:eddsa, :ed25519, private_key)
      {:ok, Base.encode16(public_key, case: :lower)}
    end
  end

  defp private_key do
    Config.signing_private_key() |> decode_private_key()
  end

  defp decode_private_key(nil), do: {:error, :signing_key_not_configured}

  defp decode_private_key(encoded_key) when is_binary(encoded_key) do
    case Base.decode64(encoded_key) do
      {:ok, key} when byte_size(key) == 32 -> {:ok, key}
      _other -> {:error, :invalid_signing_key}
    end
  end

  defp license_payload(license), do: %{data: license_data(license)}

  defp license_data(license) do
    %{
      id: license.id,
      type: "licenses",
      attributes: %{
        expiry: expiration_datetime(license.expires_on),
        metadata: %{signingKey: license.signing_key}
      }
    }
  end

  defp expiration_datetime(expires_on) do
    expires_on
    |> DateTime.new!(~T[23:59:59], "Etc/UTC")
    |> DateTime.to_iso8601()
  end

  defp active?(license), do: not Date.before?(license.expires_on, Date.utc_today())

  defp wrap_lines(contents) do
    contents
    |> String.codepoints()
    |> Enum.chunk_every(64)
    |> Enum.map_join("\n", &Enum.join/1)
  end
end
