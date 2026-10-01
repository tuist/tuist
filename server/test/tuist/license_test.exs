defmodule Tuist.LicenseTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.License

  setup :set_mimic_from_context

  describe "resolve_license/1" do
    test "returns a valid license when API returns valid data" do
      validation_url = License.get_validation_url()
      expiry = DateTime.utc_now() |> DateTime.shift(day: 1) |> Timex.format!("{RFC3339}")
      license_key = UUIDv7.generate()

      stub(Req, :post, fn ^validation_url, [json: %{meta: %{key: ^license_key}}] ->
        {:ok,
         %{
           status: 200,
           body: %{
             "data" => %{
               "id" => "1234",
               "attributes" => %{
                 "expiry" => expiry,
                 "metadata" => %{"signingKey" => "test-key"}
               }
             },
             "meta" => %{
               "valid" => true
             }
           }
         }}
      end)

      {:ok, license} = License.resolve_license(license_key)

      assert license.valid == true
      assert license.id == "1234"
      assert license.signing_key == "test-key"
    end

    test "returns nil when the license key is nil" do
      result = License.resolve_license(nil)

      assert result == {:ok, nil}
    end

    test "returns nil when API returns nil data" do
      validation_url = License.get_validation_url()
      keygen_validation_url = License.get_keygen_validation_url()
      license_key = UUIDv7.generate()

      stub(Req, :post, fn
        ^validation_url, [json: %{meta: %{key: ^license_key}}] ->
          {:ok, %{status: 200, body: %{"data" => nil}}}

        ^keygen_validation_url, [json: %{meta: %{key: ^license_key}}] ->
          {:ok, %{status: 200, body: %{"data" => nil}}}
      end)

      result = License.resolve_license(license_key)

      assert result == {:ok, nil}
    end

    test "returns invalid license when API returns valid: false" do
      validation_url = License.get_validation_url()
      expiry = DateTime.utc_now() |> DateTime.shift(day: -1) |> Timex.format!("{RFC3339}")
      license_key = UUIDv7.generate()

      stub(Req, :post, fn ^validation_url, [json: %{meta: %{key: ^license_key}}] ->
        {:ok,
         %{
           status: 200,
           body: %{
             "data" => %{
               "id" => "1234",
               "attributes" => %{
                 "expiry" => expiry
               }
             },
             "meta" => %{
               "valid" => false
             }
           }
         }}
      end)

      {:ok, license} = License.resolve_license(license_key)

      assert license.valid == false
      assert license.id == "1234"
    end

    test "falls back to Keygen when Atlas does not recognize the license" do
      validation_url = License.get_validation_url()
      keygen_validation_url = License.get_keygen_validation_url()
      expiry = DateTime.utc_now() |> DateTime.shift(day: 1) |> Timex.format!("{RFC3339}")
      license_key = UUIDv7.generate()

      stub(Req, :post, fn
        ^validation_url, [json: %{meta: %{key: ^license_key}}] ->
          {:ok, %{status: 200, body: %{"data" => nil}}}

        ^keygen_validation_url, [json: %{meta: %{key: ^license_key}}] ->
          {:ok,
           %{
             status: 200,
             body: %{
               "data" => %{
                 "id" => "1234",
                 "attributes" => %{"expiry" => expiry}
               },
               "meta" => %{"valid" => true}
             }
           }}
      end)

      {:ok, license} = License.resolve_license(license_key)

      assert license.valid == true
      assert license.id == "1234"
    end

    test "falls back to Keygen when Atlas responds with an error status" do
      validation_url = License.get_validation_url()
      keygen_validation_url = License.get_keygen_validation_url()
      expiry = DateTime.utc_now() |> DateTime.shift(day: 1) |> Timex.format!("{RFC3339}")
      license_key = UUIDv7.generate()

      stub(Req, :post, fn
        ^validation_url, [json: %{meta: %{key: ^license_key}}] ->
          {:ok, %{status: 500}}

        ^keygen_validation_url, [json: %{meta: %{key: ^license_key}}] ->
          {:ok,
           %{
             status: 200,
             body: %{
               "data" => %{
                 "id" => "1234",
                 "attributes" => %{"expiry" => expiry}
               },
               "meta" => %{"valid" => true}
             }
           }}
      end)

      {:ok, license} = License.resolve_license(license_key)

      assert license.valid == true
      assert license.id == "1234"
    end

    test "returns an error when Keygen also responds with an error status" do
      validation_url = License.get_validation_url()
      keygen_validation_url = License.get_keygen_validation_url()
      license_key = UUIDv7.generate()

      stub(Req, :post, fn
        ^validation_url, [json: %{meta: %{key: ^license_key}}] ->
          {:ok, %{status: 500}}

        ^keygen_validation_url, [json: %{meta: %{key: ^license_key}}] ->
          {:ok, %{status: 500}}
      end)

      result = License.resolve_license(license_key)

      assert {:error, "The server to validate the license responded with a 500 status code."} =
               result
    end

    test "falls back to Keygen when the Atlas request errors" do
      validation_url = License.get_validation_url()
      keygen_validation_url = License.get_keygen_validation_url()
      expiry = DateTime.utc_now() |> DateTime.shift(day: 1) |> Timex.format!("{RFC3339}")
      license_key = UUIDv7.generate()

      stub(Req, :post, fn
        ^validation_url, [json: %{meta: %{key: ^license_key}}] ->
          {:error, "atlas error"}

        ^keygen_validation_url, [json: %{meta: %{key: ^license_key}}] ->
          {:ok,
           %{
             status: 200,
             body: %{
               "data" => %{
                 "id" => "1234",
                 "attributes" => %{"expiry" => expiry}
               },
               "meta" => %{"valid" => true}
             }
           }}
      end)

      {:ok, license} = License.resolve_license(license_key)

      assert license.valid == true
      assert license.id == "1234"
    end
  end

  describe "resolve_certificate/2" do
    test "decodes an environment certificate containing whitespace" do
      encoded = Base.encode64("certificate")
      wrapped = String.slice(encoded, 0, 4) <> "\n  " <> String.slice(encoded, 4..-1//1)

      assert License.certificate(wrapped) == "certificate"
    end

    test "returns valid license when certificate is valid with real signed data" do
      {public_key, private_key} = :crypto.generate_key(:eddsa, :ed25519)
      verify_key = Base.encode16(public_key, case: :lower)

      license_payload = %{
        "data" => %{
          "id" => "test-license-id",
          "type" => "licenses",
          "attributes" => %{
            "expiry" => DateTime.utc_now() |> DateTime.shift(day: 30) |> DateTime.to_iso8601(),
            "metadata" => %{
              "signingKey" => "test-signing-key-base64"
            }
          }
        }
      }

      encoded_data = license_payload |> JSON.encode!() |> Base.encode64()
      data_to_sign = "license/" <> encoded_data
      signature = :crypto.sign(:eddsa, :none, data_to_sign, [private_key, :ed25519])
      signature_base64 = Base.encode64(signature)

      certificate =
        %{
          "enc" => encoded_data,
          "sig" => signature_base64,
          "alg" => "base64+ed25519"
        }
        |> JSON.encode!()
        |> Base.encode64()

      result = License.resolve_certificate(verify_key, certificate)

      assert {:ok, license} = result
      assert license.id == "test-license-id"
      assert license.valid == true
      assert license.signing_key == "test-signing-key-base64"
    end

    test "returns valid license when certificate is signed by one of the trusted verify keys" do
      {trusted_public_key, _trusted_private_key} = :crypto.generate_key(:eddsa, :ed25519)
      {atlas_public_key, atlas_private_key} = :crypto.generate_key(:eddsa, :ed25519)

      verify_keys = [
        Base.encode16(atlas_public_key, case: :lower),
        Base.encode16(trusted_public_key, case: :lower)
      ]

      license_payload = %{
        "data" => %{
          "id" => "test-license-id",
          "attributes" => %{
            "expiry" => DateTime.utc_now() |> DateTime.shift(day: 1) |> DateTime.to_iso8601(),
            "metadata" => %{"signingKey" => "test-signing-key-base64"}
          }
        }
      }

      encoded_data = license_payload |> JSON.encode!() |> Base.encode64()

      signature =
        :crypto.sign(:eddsa, :none, "license/" <> encoded_data, [atlas_private_key, :ed25519])

      certificate =
        %{"enc" => encoded_data, "sig" => Base.encode64(signature), "alg" => "base64+ed25519"}
        |> JSON.encode!()
        |> Base.encode64()

      assert {:ok, license} = License.resolve_certificate(verify_keys, certificate)
      assert license.id == "test-license-id"
    end

    test "returns error when signature is invalid" do
      {public_key, _private_key} = :crypto.generate_key(:eddsa, :ed25519)
      {_other_public, other_private} = :crypto.generate_key(:eddsa, :ed25519)
      verify_key = Base.encode16(public_key, case: :lower)

      license_payload = %{
        "data" => %{
          "id" => "test-license-id",
          "type" => "licenses",
          "attributes" => %{
            "expiry" => DateTime.utc_now() |> DateTime.shift(day: 30) |> DateTime.to_iso8601(),
            "metadata" => %{}
          }
        }
      }

      encoded_data = license_payload |> JSON.encode!() |> Base.encode64()
      data_to_sign = "license/" <> encoded_data
      signature = :crypto.sign(:eddsa, :none, data_to_sign, [other_private, :ed25519])
      signature_base64 = Base.encode64(signature)

      certificate =
        %{
          "enc" => encoded_data,
          "sig" => signature_base64,
          "alg" => "base64+ed25519"
        }
        |> JSON.encode!()
        |> Base.encode64()

      result = License.resolve_certificate(verify_key, certificate)

      assert {:error, "Invalid signature"} = result
    end

    test "returns error when certificate has invalid format" do
      verify_key = "58f8d43c65b5a3e200e8ef6ecefa6b700432124527edf50a5b5b0577242c51fd"

      certificate =
        %{
          "data" => "some data"
        }
        |> JSON.encode!()
        |> Base.encode64()

      result = License.resolve_certificate(verify_key, certificate)

      assert {:error, "Invalid certificate format - missing required fields"} = result
    end

    test "returns error when certificate is not valid base64" do
      verify_key = "58f8d43c65b5a3e200e8ef6ecefa6b700432124527edf50a5b5b0577242c51fd"
      certificate = "not-valid-base64!!!"

      result = License.resolve_certificate(verify_key, certificate)

      assert {:error, "Failed to decode base64 certificate"} = result
    end

    test "returns error when certificate contains invalid JSON" do
      verify_key = "58f8d43c65b5a3e200e8ef6ecefa6b700432124527edf50a5b5b0577242c51fd"
      certificate = Base.encode64("not json at all")

      result = License.resolve_certificate(verify_key, certificate)

      assert {:error, _} = result
    end
  end

  describe "get_license/1 dispatching on TUIST_LICENSE" do
    setup do
      stub(Tuist.KeyValueStore, :get_or_update, fn _key, _opts, func -> func.() end)

      stub(Tuist.Environment, :license_key, fn -> nil end)
      stub(Tuist.Environment, :license_certificate_base64, fn -> nil end)
      stub(Tuist.Environment, :license_verify_key, fn -> nil end)

      :ok
    end

    test "treats a plain license key value as an online license" do
      validation_url = License.get_validation_url()
      expiry = DateTime.utc_now() |> DateTime.shift(day: 1) |> Timex.format!("{RFC3339}")
      license_key = UUIDv7.generate()

      stub(Tuist.Environment, :license_value, fn -> license_key end)

      stub(Req, :post, fn ^validation_url, [json: %{meta: %{key: ^license_key}}] ->
        {:ok,
         %{
           status: 200,
           body: %{
             "data" => %{
               "id" => "1234",
               "attributes" => %{
                 "expiry" => expiry,
                 "metadata" => %{"signingKey" => "test-key"}
               }
             },
             "meta" => %{"valid" => true}
           }
         }}
      end)

      assert {:ok, license} = License.get_license()
      assert license.id == "1234"
      assert license.valid == true
    end

    test "treats a base64-encoded certificate value as an air-gapped license" do
      {public_key, private_key} = :crypto.generate_key(:eddsa, :ed25519)
      verify_key = Base.encode16(public_key, case: :lower)
      stub(Tuist.Environment, :license_verify_key, fn -> verify_key end)

      license_payload = %{
        "data" => %{
          "id" => "air-gapped-id",
          "attributes" => %{
            "expiry" => DateTime.utc_now() |> DateTime.shift(day: 30) |> DateTime.to_iso8601(),
            "metadata" => %{"signingKey" => "signing-key"}
          }
        }
      }

      encoded_data = license_payload |> JSON.encode!() |> Base.encode64()

      signature =
        :crypto.sign(:eddsa, :none, "license/" <> encoded_data, [private_key, :ed25519])

      certificate =
        %{"enc" => encoded_data, "sig" => Base.encode64(signature), "alg" => "base64+ed25519"}
        |> JSON.encode!()
        |> Base.encode64()

      stub(Tuist.Environment, :license_value, fn -> certificate end)

      assert {:ok, license} = License.get_license()
      assert license.id == "air-gapped-id"
      assert license.valid == true
    end

    test "treats a PEM-wrapped certificate value as an air-gapped license" do
      {public_key, private_key} = :crypto.generate_key(:eddsa, :ed25519)
      verify_key = Base.encode16(public_key, case: :lower)
      stub(Tuist.Environment, :license_verify_key, fn -> verify_key end)

      license_payload = %{
        "data" => %{
          "id" => "pem-wrapped-id",
          "attributes" => %{
            "expiry" => DateTime.utc_now() |> DateTime.shift(day: 30) |> DateTime.to_iso8601(),
            "metadata" => %{"signingKey" => "signing-key"}
          }
        }
      }

      encoded_data = license_payload |> JSON.encode!() |> Base.encode64()

      signature =
        :crypto.sign(:eddsa, :none, "license/" <> encoded_data, [private_key, :ed25519])

      certificate_body =
        %{"enc" => encoded_data, "sig" => Base.encode64(signature), "alg" => "base64+ed25519"}
        |> JSON.encode!()
        |> Base.encode64()

      wrapped =
        "-----BEGIN LICENSE FILE-----\n" <>
          certificate_body <> "\n-----END LICENSE FILE-----\n"

      stub(Tuist.Environment, :license_value, fn -> wrapped end)

      assert {:ok, license} = License.get_license()
      assert license.id == "pem-wrapped-id"
    end
  end

  describe "ed25519_verify_keys/0" do
    test "trusts the Atlas and Keygen verify keys without extra configuration" do
      stub(Tuist.Environment, :license_verify_key, fn -> nil end)

      assert License.ed25519_verify_keys() == [
               License.atlas_ed25519_verify_key(),
               License.ed25519_verify_key()
             ]
    end

    test "trusts an additional verify key from the environment" do
      verify_key = Base.encode16(:crypto.strong_rand_bytes(32), case: :lower)
      stub(Tuist.Environment, :license_verify_key, fn -> verify_key end)

      assert License.ed25519_verify_keys() == [
               verify_key,
               License.atlas_ed25519_verify_key(),
               License.ed25519_verify_key()
             ]
    end
  end
end
