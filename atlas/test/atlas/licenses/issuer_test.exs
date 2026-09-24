defmodule Atlas.Licenses.IssuerTest do
  use ExUnit.Case, async: true

  alias Atlas.Licenses.Issuer
  alias Atlas.Licenses.License

  test "issues an opaque online key and per-license request signing key" do
    expires_on = Date.utc_today() |> Date.add(365)

    issued = Issuer.issue(expires_on)

    assert issued.key =~ ~r/^tuist_[A-Za-z0-9_-]+$/
    assert issued.key_hash == Issuer.key_hash(issued.key)
    assert byte_size(Base.decode64!(issued.signing_key)) == 32
    assert issued.expires_on == expires_on
  end

  test "creates an Ed25519 certificate in Tuist's air-gapped format" do
    license = %License{
      id: Ecto.UUID.generate(),
      signing_key: Base.encode64(:crypto.strong_rand_bytes(32)),
      expires_on: ~D[2027-08-31]
    }

    assert {:ok, certificate} = Issuer.certificate(license)
    assert certificate =~ "BEGIN LICENSE FILE"

    envelope = decode_certificate(certificate)
    assert envelope["alg"] == "base64+ed25519"

    {:ok, verify_key} = Issuer.public_key()
    public_key = Base.decode16!(verify_key, case: :lower)
    signature = Base.decode64!(envelope["sig"])

    assert :crypto.verify(
             :eddsa,
             :none,
             "license/" <> envelope["enc"],
             signature,
             [public_key, :ed25519]
           )

    payload = envelope["enc"] |> Base.decode64!() |> JSON.decode!()
    assert payload["data"]["id"] == license.id
    assert payload["data"]["attributes"]["expiry"] == "2027-08-31T23:59:59Z"
    assert payload["data"]["attributes"]["metadata"]["signingKey"] == license.signing_key
  end

  test "builds the online validation response expected by Tuist" do
    license = %License{
      id: Ecto.UUID.generate(),
      signing_key: Base.encode64(:crypto.strong_rand_bytes(32)),
      expires_on: Date.utc_today() |> Date.add(1)
    }

    assert %{data: data, meta: %{valid: true}} = Issuer.validation_payload(license)
    assert data.id == license.id
    assert data.attributes.metadata.signingKey == license.signing_key
    assert Issuer.validation_payload(nil) == %{data: nil, meta: %{valid: false}}
  end

  defp decode_certificate(certificate) do
    certificate
    |> String.replace(~r/-----.*?-----/s, "")
    |> String.replace(~r/\s/, "")
    |> Base.decode64!()
    |> JSON.decode!()
  end
end
