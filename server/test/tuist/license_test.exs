defmodule Tuist.LicenseTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.License

  setup :set_mimic_from_context

  describe "resolve_license/1" do
    test "returns a valid license when API returns valid data" do
      # Given
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

      # When
      {:ok, license} = License.resolve_license(license_key)

      # Then
      assert license.valid == true
      assert license.id == "1234"
      assert license.signing_key == "test-key"
    end

    test "returns nil when the license key is nil" do
      # When
      result = License.resolve_license(nil)

      # Then
      assert result == {:ok, nil}
    end

    test "returns nil when API returns nil data" do
      # Given
      validation_url = License.get_validation_url()
      license_key = UUIDv7.generate()

      stub(Req, :post, fn ^validation_url, [json: %{meta: %{key: ^license_key}}] ->
        {:ok, %{status: 200, body: %{"data" => nil}}}
      end)

      # When
      result = License.resolve_license(license_key)

      # Then
      assert result == {:ok, nil}
    end

    test "returns invalid license when API returns valid: false" do
      # Given
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

      # When
      {:ok, license} = License.resolve_license(license_key)

      # Then
      assert license.valid == false
      assert license.id == "1234"
    end

    test "returns error when the server responds with error status" do
      # Given
      validation_url = License.get_validation_url()
      license_key = UUIDv7.generate()

      stub(Req, :post, fn ^validation_url, [json: %{meta: %{key: ^license_key}}] ->
        {:ok, %{status: 500}}
      end)

      # When
      result = License.resolve_license(license_key)

      # Then
      assert {:error, "The server to validate the license responded with a 500 status code."} = result
    end

    test "returns error when the Req errors" do
      # Given
      validation_url = License.get_validation_url()
      license_key = UUIDv7.generate()

      stub(Req, :post, fn ^validation_url, [json: %{meta: %{key: ^license_key}}] ->
        {:error, "req error."}
      end)

      # When
      result = License.resolve_license(license_key)

      # Then
      assert {:error, "\"req error.\""} = result
    end
  end

  describe "resolve_certificate/2" do
    test "returns valid license when certificate is valid with real signed data" do
      # Generate a test Ed25519 key pair
      {public_key, private_key} = :crypto.generate_key(:eddsa, :ed25519)

      # Convert public key to hex for use as verify_key
      verify_key = Base.encode16(public_key, case: :lower)

      # Create license data with future expiry
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

      # Base64 encode the license data
      encoded_data = license_payload |> Jason.encode!() |> Base.encode64()

      # Create the data to sign (following Keygen's format)
      data_to_sign = "license/" <> encoded_data

      # Sign with the private key
      signature = :crypto.sign(:eddsa, :none, data_to_sign, [private_key, :ed25519])
      signature_base64 = Base.encode64(signature)

      # Create the certificate
      certificate =
        %{
          "enc" => encoded_data,
          "sig" => signature_base64,
          "alg" => "base64+ed25519"
        }
        |> Jason.encode!()
        |> Base.encode64()

      # When
      result = License.resolve_certificate(verify_key, certificate)

      # Then
      assert {:ok, license} = result
      assert license.id == "test-license-id"
      assert license.valid == true
      assert license.signing_key == "test-signing-key-base64"
    end

    test "returns error when signature is invalid" do
      # Generate a test Ed25519 key pair
      {public_key, _private_key} = :crypto.generate_key(:eddsa, :ed25519)

      # Generate a DIFFERENT key pair for signing (to create invalid signature)
      {_other_public, other_private} = :crypto.generate_key(:eddsa, :ed25519)

      # Convert public key to hex for use as verify_key
      verify_key = Base.encode16(public_key, case: :lower)

      # Create license data
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

      # Base64 encode the license data
      encoded_data = license_payload |> Jason.encode!() |> Base.encode64()

      # Create the data to sign
      data_to_sign = "license/" <> encoded_data

      # Sign with the WRONG private key
      signature = :crypto.sign(:eddsa, :none, data_to_sign, [other_private, :ed25519])
      signature_base64 = Base.encode64(signature)

      # Create the certificate
      certificate =
        %{
          "enc" => encoded_data,
          "sig" => signature_base64,
          "alg" => "base64+ed25519"
        }
        |> Jason.encode!()
        |> Base.encode64()

      # When
      result = License.resolve_certificate(verify_key, certificate)

      # Then
      assert {:error, "Invalid signature"} = result
    end

    test "returns error when certificate has invalid format" do
      # Given
      verify_key = "58f8d43c65b5a3e200e8ef6ecefa6b700432124527edf50a5b5b0577242c51fd"

      # Invalid certificate - missing required fields
      certificate =
        %{
          "data" => "some data"
        }
        |> Jason.encode!()
        |> Base.encode64()

      # When
      result = License.resolve_certificate(verify_key, certificate)

      # Then
      assert {:error, "Invalid certificate format - missing required fields"} = result
    end

    test "returns error when certificate is not valid base64" do
      # Given
      verify_key = "58f8d43c65b5a3e200e8ef6ecefa6b700432124527edf50a5b5b0577242c51fd"
      certificate = "not-valid-base64!!!"

      # When
      result = License.resolve_certificate(verify_key, certificate)

      # Then
      assert {:error, "Failed to decode base64 certificate"} = result
    end

    test "returns error when certificate contains invalid JSON" do
      # Given
      verify_key = "58f8d43c65b5a3e200e8ef6ecefa6b700432124527edf50a5b5b0577242c51fd"
      certificate = Base.encode64("not json at all")

      # When
      result = License.resolve_certificate(verify_key, certificate)

      # Then
      assert {:error, _} = result
    end
  end
end
