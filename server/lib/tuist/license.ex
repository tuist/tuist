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
    ttl = Keyword.get(opts, :ttl, to_timeout(day: 1))

    KeyValueStore.get_or_update(
      [__MODULE__, "license"],
      [ttl: ttl],
      fn -> fetch_license() end
    )
  end

  defp fetch_license do
    cond do
      key = Tuist.Environment.license_key() ->
        resolve_license(key)

      Tuist.Environment.license_certificate_base64() ->
        resolve_certificate()

      true ->
        {:error, :license_not_found}
    end
  end

  # Ed25519 128-bit Verify Key
  def ed25519_verify_key do
    "58f8d43c65b5a3e200e8ef6ecefa6b700432124527edf50a5b5b0577242c51fd"
  end

  def certificate do
    Base.decode64!(Tuist.Environment.license_certificate_base64())
  end

  @doc """
  Resolves a license from a certificate, validating it against the Ed25519 verify key.

  Returns {:ok, %Tuist.License{}} if valid, {:error, reason} otherwise.

  Supports Keygen offline license format with Ed25519 signatures.
  """
  def resolve_certificate(verify_key \\ ed25519_verify_key(), certificate \\ certificate()) do
    cert_content =
      certificate
      |> String.replace(~r/-----.*?-----/s, "")
      |> String.replace(~r/\s/, "")
      |> String.trim()

    with {:ok, decoded} <- Base.decode64(cert_content),
         {:ok, payload} <- Jason.decode(decoded) do
      case payload do
        %{"enc" => enc_data, "sig" => sig_data, "alg" => alg} ->
          verify_and_build_license(verify_key, enc_data, sig_data, alg)

        %{"data" => data, "sig" => sig, "alg" => alg} ->
          verify_and_build_license(verify_key, data, sig, alg)

        _ ->
          {:error, "Invalid certificate format - missing required fields"}
      end
    else
      :error ->
        {:error, "Failed to decode base64 certificate"}

      {:error, %Jason.DecodeError{} = error} ->
        {:error, "Invalid certificate JSON: #{Exception.message(error)}"}
    end
  end

  defp verify_and_build_license(verify_key, enc_data, signature, _algorithm) do
    with {:ok, public_key} <- Base.decode16(verify_key, case: :lower),
         {:ok, sig_binary} <- Base.decode64(signature) do
      # For Ed25519 signatures, verify against "license/" + base64 data
      data_to_verify = "license/" <> enc_data

      if :crypto.verify(:eddsa, :none, data_to_verify, sig_binary, [public_key, :ed25519]) do
        case Base.decode64(enc_data) do
          {:ok, decoded} ->
            case JSON.decode(decoded) do
              {:ok, license_data} -> build_license_struct(license_data)
              {:error, _} -> {:error, "Failed to parse license data"}
            end

          :error ->
            {:error, "Failed to decode license data"}
        end
      else
        {:error, "Invalid signature"}
      end
    else
      :error ->
        {:error, "Failed to decode verify key or signature"}
    end
  end

  defp build_license_struct(license_data) do
    # Extract the main data section
    data = license_data["data"]
    attributes = data["attributes"]
    metadata = attributes["metadata"] || %{}

    # Determine validity based on expiry and status
    expiry = attributes["expiry"]

    valid =
      case DateTime.from_iso8601(expiry) do
        {:ok, exp_date, _} -> DateTime.after?(exp_date, DateTime.utc_now())
        _ -> false
      end

    {:ok,
     %__MODULE__{
       id: data["id"],
       valid: valid,
       features: [],
       expiration_date: parse_datetime(expiry),
       signing_key: metadata["signingKey"]
     }}
  end

  defp parse_datetime(nil), do: nil

  defp parse_datetime(datetime_string) do
    case DateTime.from_iso8601(datetime_string) do
      {:ok, datetime, _} -> datetime
      _ -> nil
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

        {:error, :license_not_found} ->
          raise "The license key exposed through the environment variable TUIST_LICENSE or TUIST_LICENSE_KEY is missing."

        {:ok, nil} ->
          raise "The license key is invalid or does not exist."

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
