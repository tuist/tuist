defmodule Tuist.License do
  @moduledoc ~S"""
  Interface to check the environment licenses.
  """

  alias Tuist.KeyValueStore

  require Logger

  @atlas_validation_url "https://atlas.tuist.dev/api/licenses/actions/validate-key"
  @keygen_validation_url "https://api.keygen.sh/v1/accounts/cce51171-9339-4430-8441-73bb5abd9a5c/licenses/actions/validate-key"

  @enforce_keys [:id, :features, :expiration_date, :valid]
  defstruct [:id, :features, :expiration_date, :valid, :signing_key]

  def get_validation_url do
    @atlas_validation_url
  end

  def get_keygen_validation_url do
    @keygen_validation_url
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

  def get_cached_license do
    KeyValueStore.get([__MODULE__, "license"])
  end

  defp fetch_license do
    cond do
      Tuist.Environment.license_certificate_base64() ->
        resolve_certificate()

      key = Tuist.Environment.license_key() ->
        resolve_license(key)

      true ->
        {:error, :license_not_found}
    end
  end

  # Ed25519 128-bit Verify Key
  def ed25519_verify_key do
    "58f8d43c65b5a3e200e8ef6ecefa6b700432124527edf50a5b5b0577242c51fd"
  end

  def ed25519_verify_keys do
    [Tuist.Environment.license_verify_key(), ed25519_verify_key()]
    |> Enum.filter(&(is_binary(&1) and &1 != ""))
    |> Enum.uniq()
  end

  def certificate(encoded \\ Tuist.Environment.license_certificate_base64()) do
    Base.decode64!(encoded, ignore: :whitespace)
  end

  @doc """
  Resolves a license from a certificate, validating it against the Ed25519 verify key.

  Returns {:ok, %Tuist.License{}} if valid, {:error, reason} otherwise.

  Supports Keygen offline license format with Ed25519 signatures.
  """
  def resolve_certificate(verify_keys \\ ed25519_verify_keys(), certificate \\ certificate()) do
    cert_content =
      certificate
      |> String.replace(~r/-----.*?-----/s, "")
      |> String.replace(~r/\s/, "")
      |> String.trim()

    with {:ok, decoded} <- Base.decode64(cert_content),
         {:ok, payload} <- JSON.decode(decoded) do
      case payload do
        %{"enc" => enc_data, "sig" => sig_data, "alg" => alg} ->
          verify_and_build_license(verify_keys, enc_data, sig_data, alg)

        %{"data" => data, "sig" => sig, "alg" => alg} ->
          verify_and_build_license(verify_keys, data, sig, alg)

        _ ->
          {:error, "Invalid certificate format - missing required fields"}
      end
    else
      :error ->
        {:error, "Failed to decode base64 certificate"}

      {:error, reason} ->
        {:error, "Invalid certificate JSON: #{inspect(reason)}"}
    end
  end

  defp verify_and_build_license(verify_keys, enc_data, signature, _algorithm) do
    with {:ok, public_keys} <- decode_verify_keys(verify_keys),
         {:ok, sig_binary} <- Base.decode64(signature),
         :ok <- verify_license_signature(public_keys, enc_data, sig_binary),
         {:ok, decoded} <- decode_license_data(enc_data),
         {:ok, license_data} <- decode_license_json(decoded) do
      build_license_struct(license_data)
    else
      :error ->
        {:error, "Failed to decode verify key or signature"}

      {:error, :invalid_signature} ->
        {:error, "Invalid signature"}

      {:error, :failed_to_decode_license_data} ->
        {:error, "Failed to decode license data"}

      {:error, :failed_to_parse_license_data} ->
        {:error, "Failed to parse license data"}
    end
  end

  defp decode_verify_keys(verify_keys) do
    public_keys =
      verify_keys
      |> List.wrap()
      |> Enum.map(&Base.decode16(&1, case: :lower))

    if Enum.all?(public_keys, &match?({:ok, _}, &1)) do
      {:ok, Enum.map(public_keys, fn {:ok, public_key} -> public_key end)}
    else
      :error
    end
  end

  defp verify_license_signature(public_keys, enc_data, signature) do
    if Enum.any?(public_keys, fn public_key ->
         :crypto.verify(:eddsa, :none, "license/" <> enc_data, signature, [public_key, :ed25519])
       end) do
      :ok
    else
      {:error, :invalid_signature}
    end
  end

  defp decode_license_data(enc_data) do
    case Base.decode64(enc_data) do
      {:ok, decoded} -> {:ok, decoded}
      :error -> {:error, :failed_to_decode_license_data}
    end
  end

  defp decode_license_json(decoded) do
    case JSON.decode(decoded) do
      {:ok, license_data} -> {:ok, license_data}
      {:error, _} -> {:error, :failed_to_parse_license_data}
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
    case resolve_license_from_atlas(key) do
      {:ok, license} ->
        {:ok, license}

      {:fallback, reason} ->
        Logger.warning("Atlas did not validate the license (#{inspect(reason)}); falling back to Keygen.")

        resolve_license_from_keygen(key)
    end
  end

  defp resolve_license_from_atlas(key) do
    Logger.debug("Validating the license against Atlas...")

    case validate_license(@atlas_validation_url, key) do
      {:ok, %{"data" => nil}} ->
        {:fallback, :license_not_found}

      {:ok, payload} ->
        case build_license(payload) do
          {:ok, license} -> {:ok, license}
          {:error, reason} -> {:fallback, reason}
        end

      {:error, reason} ->
        {:fallback, reason}
    end
  end

  defp resolve_license_from_keygen(key) do
    Logger.debug("Validating the license against Keygen...")

    with {:ok, payload} <- validate_license(@keygen_validation_url, key) do
      build_license(payload)
    end
  end

  defp validate_license(url, key) do
    case Req.post(url, json: %{meta: %{key: key}}) do
      {:ok, %{body: payload, status: status}} when status in 200..299 ->
        {:ok, payload}

      {:ok, %{status: status}} when status in 400..599 ->
        {:error, "The server to validate the license responded with a #{status} status code."}

      {:error, error} ->
        {:error, inspect(error)}
    end
  end

  defp build_license(%{"data" => nil}), do: {:ok, nil}

  defp build_license(%{
         "data" => %{"id" => id, "attributes" => %{"expiry" => expiry} = attributes},
         "meta" => %{"valid" => valid}
       }) do
    signing_key = (attributes["metadata"] || %{})["signingKey"]

    {:ok,
     %__MODULE__{
       valid: valid,
       id: id,
       features: [],
       expiration_date: Timex.parse!(expiry, "{RFC3339}"),
       signing_key: signing_key
     }}
  end

  defp build_license(_payload), do: {:error, :invalid_license_response}
end
