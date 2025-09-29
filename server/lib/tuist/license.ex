defmodule Tuist.License do
  @moduledoc ~S"""
  Interface to check the environment licenses.
  """

  alias Tuist.KeyValueStore

  require Logger

  @validation_url "https://api.keygen.sh/v1/accounts/cce51171-9339-4430-8441-73bb5abd9a5c/licenses/actions/validate-key"

  @enforce_keys [:id, :features, :expiration_date, :valid]
  defstruct [:id, :features, :expiration_date, :valid, :signing_key]

  def get_validation_url do
    @validation_url
  end

  def sign(value) when is_binary(value) do
    if Tuist.Environment.dev?() or Tuist.Environment.test?() do
      nil
    else
      {:ok, %{signing_key: key_base64}} = get_license()
      key = Base.decode64!(key_base64)
      signature = :crypto.mac(:hmac, :sha256, key, value)
      Base.encode64(signature)
    end
  end

  def get_license(opts \\ []) do
    case KeyValueStore.get_or_update(
           [__MODULE__, "license"],
           [
             ttl: Keyword.get(opts, :ttl, to_timeout(day: 1))
           ],
           fn ->
             resolve_license(Tuist.Environment.license_key())
           end
         ) do
      {:ok, license} -> {:ok, license}
      {:error, error} -> {:error, error}
    end
  end

  # ECDSA P-256 Public Key
  def ecdsa_p256_public_key() do
    "LS0tLS1CRUdJTiBQVUJMSUMgS0VZLS0tLS0KTUZrd0V3WUhLb1pJemowQ0FRWUlLb1pJemowREFRY0RRZ0FFY2hMOEFTNFUxRStTV3JrS1hhdjA4ek5tc0tMTQpuaEg2MFNqdzlxQ214WmZnVTlLU2orUEo1NnpCb01GNUx3YTBZamhjNUNsSDdlZjliUnB4U3FJVmNBPT0KLS0tLS1FTkQgUFVCTElDIEtFWS0tLS0tCg=="
  end

  def license_certificate() do
    Tuist.Environment.license_certificate_base64() |> Base.decode64!()
  end

  @doc """
  Validates a license certificate against the ECDSA P-256 public key.

  Returns {:ok, certificate_data} if valid, {:error, reason} otherwise.

  Supports Keygen offline license format with ECDSA P-256 signatures.
  """
  def validate_license_certificate(public_key_pem \\ ecdsa_p256_public_key(), certificate \\ license_certificate()) do
    try do
      # Debug: log the first part of the certificate
      IO.inspect(String.slice(certificate, 0, 100), label: "Certificate preview")

      # Remove PEM headers if present
      cert_content = certificate
        |> String.replace("-----BEGIN LICENSE FILE-----", "")
        |> String.replace("-----END LICENSE FILE-----", "")
        |> String.replace("-----BEGIN LICENSE KEY-----", "")
        |> String.replace("-----END LICENSE KEY-----", "")
        |> String.trim()

      # Try to decode as base64
      decoded = case Base.decode64(cert_content) do
        {:ok, decoded_data} ->
          IO.inspect(String.slice(decoded_data, 0, 100), label: "Decoded preview")
          decoded_data
        :error ->
          IO.puts("Base64 decode failed, using raw content")
          cert_content
      end
      dbg(decoded)


      # Parse the decoded content
      case Jason.decode(decoded) do
        {:ok, %{"enc" => enc_data, "sig" => sig_data, "alg" => alg}} ->
          IO.inspect(alg, label: "Algorithm")
          # This is a Keygen offline license with encryption and signature
          verify_keygen_license(public_key_pem, enc_data, sig_data, alg)

        {:ok, %{"data" => data, "sig" => sig, "alg" => alg}} ->
          IO.inspect(alg, label: "Algorithm")
          # Simplified format without encryption
          verify_keygen_license(public_key_pem, data, sig, alg)

        {:ok, payload} when is_map(payload) ->
          IO.inspect(Map.keys(payload), label: "JSON keys")
          # For dev/test, allow unsigned payloads
          if Tuist.Environment.dev?() or Tuist.Environment.test?() do
            {:ok, payload}
          else
            {:error, "Certificate missing signature - keys: #{inspect(Map.keys(payload))}"}
          end

        {:error, error} ->
          IO.inspect(error, label: "JSON parse error")
          {:error, "Invalid certificate format - not a valid Keygen license"}

        other ->
          IO.inspect(other, label: "Unexpected JSON result")
          {:error, "Invalid certificate format"}
      end
    rescue
      e ->
        {:error, "Certificate validation failed: #{inspect(e)}"}
    end
  end

  defp verify_keygen_license(public_key_pem, data, signature, algorithm) do
    try do
      # Decode the PEM public key
      public_key = public_key_pem |> Base.decode64!()

      # Determine the signing algorithm
      case String.downcase(algorithm) do
        alg when alg in ["ecdsa-p256", "base64+ecdsa-p256", "aes-256-gcm+ecdsa-p256"] ->
          # Parse the public key for ECDSA
          [{:SubjectPublicKeyInfo, der_public_key, _}] = :public_key.pem_decode(public_key)
          ec_key = :public_key.der_decode(:SubjectPublicKeyInfo, der_public_key)

          # Prepare the data for verification
          data_to_verify = if is_binary(data), do: data, else: Jason.encode!(data)

          # Decode the signature
          sig_binary = Base.decode64!(signature)

          # Verify using ECDSA with SHA256
          case :public_key.verify(data_to_verify, :sha256, sig_binary, ec_key) do
            true ->
              # Parse the data if it's encoded
              parsed_data = case Jason.decode(data_to_verify) do
                {:ok, parsed} -> parsed
                {:error, _} -> data
              end
              {:ok, parsed_data}
            false ->
              {:error, "Invalid signature"}
          end

        _ ->
          {:error, "Unsupported algorithm: #{algorithm}"}
      end
    rescue
      e ->
        {:error, "Keygen license verification failed: #{inspect(e)}"}
    end
  end

  def assert_valid!(opts \\ []) do
    Logger.info("Validating the license...")

    if Tuist.Environment.dev?() or Tuist.Environment.test?() do
      :ok
    else
      case get_license(opts) do
        {:ok, %{valid: true}} ->
          :ok

        {:ok, nil} ->
          raise "The license key exposed through the environment variable TUIST_LICENSE or TUIST_LICENSE_KEY is missing."

        {:ok, %{valid: false}} ->
          raise "The license key is invalid or expired. Please, contact contact@tuist.dev to get a new one."

        {:error, error} ->
          raise "The license validation failed with the following error: #{error}"
      end
    end
  end

  def resolve_license(key) when is_nil(key) do
    {:ok, nil}
  end

  def resolve_license(key) when not is_nil(key) do
    Logger.debug("Validating the license against the Keygen API...")

    url =
      "https://api.keygen.sh/v1/accounts/cce51171-9339-4430-8441-73bb5abd9a5c/licenses/actions/validate-key"

    case Req.post(url, json: %{meta: %{key: key}}) do
      {:ok, %{body: payload, status: status}} when status in 200..299 ->
        # When the license doesn't exist, keygen's API returns a 2xx response with "data" set to nil in the payload.
        if is_nil(payload["data"]) do
          {:ok, nil}
        else
          signing_key =
            (payload["data"]["attributes"]["metadata"] || %{})["signingKey"]

          {:ok,
           %__MODULE__{
             valid: payload["meta"]["valid"],
             id: payload["data"]["id"],
             features: [],
             expiration_date: Timex.parse!(payload["data"]["attributes"]["expiry"], "{RFC3339}"),
             signing_key: signing_key
           }}
        end

      {:ok, %{status: status}} when status in 400..599 ->
        {:error, "The server to validate the license responded with a #{status} status code."}

      {:error, error} ->
        {:error, inspect(error)}
    end
  end
end
