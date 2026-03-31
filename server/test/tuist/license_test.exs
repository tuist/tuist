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
      license_key = UUIDv7.generate()

      stub(Req, :post, fn ^validation_url, [json: %{meta: %{key: ^license_key}}] ->
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

    test "returns error when the server responds with error status" do
      validation_url = License.get_validation_url()
      license_key = UUIDv7.generate()

      stub(Req, :post, fn ^validation_url, [json: %{meta: %{key: ^license_key}}] ->
        {:ok, %{status: 500}}
      end)

      result = License.resolve_license(license_key)

      assert {:error, "The server to validate the license responded with a 500 status code."} = result
    end

    test "returns error when the Req errors" do
      validation_url = License.get_validation_url()
      license_key = UUIDv7.generate()

      stub(Req, :post, fn ^validation_url, [json: %{meta: %{key: ^license_key}}] ->
        {:error, "req error."}
      end)

      result = License.resolve_license(license_key)

      assert {:error, "\"req error.\""} = result
    end
  end

  describe "resolve_certificate/2" do
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

      encoded_data = license_payload |> Jason.encode!() |> Base.encode64()
      data_to_sign = "license/" <> encoded_data
      signature = :crypto.sign(:eddsa, :none, data_to_sign, [private_key, :ed25519])
      signature_base64 = Base.encode64(signature)

      certificate =
        %{
          "enc" => encoded_data,
          "sig" => signature_base64,
          "alg" => "base64+ed25519"
        }
        |> Jason.encode!()
        |> Base.encode64()

      result = License.resolve_certificate(verify_key, certificate)

      assert {:ok, license} = result
      assert license.id == "test-license-id"
      assert license.valid == true
      assert license.signing_key == "test-signing-key-base64"
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

      encoded_data = license_payload |> Jason.encode!() |> Base.encode64()
      data_to_sign = "license/" <> encoded_data
      signature = :crypto.sign(:eddsa, :none, data_to_sign, [other_private, :ed25519])
      signature_base64 = Base.encode64(signature)

      certificate =
        %{
          "enc" => encoded_data,
          "sig" => signature_base64,
          "alg" => "base64+ed25519"
        }
        |> Jason.encode!()
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
        |> Jason.encode!()
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
end
