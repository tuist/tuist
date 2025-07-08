defmodule Tuist.License do
  @moduledoc ~S"""
  Interface to check the environment licenses.
  """

  alias Tuist.KeyValueStore

  require Logger

  @validation_url "https://api.keygen.sh/v1/accounts/cce51171-9339-4430-8441-73bb5abd9a5c/licenses/actions/validate-key"

  @enforce_keys [:id, :features, :expiration_date, :valid]
  defstruct [:id, :features, :expiration_date, :valid, :signing_certificate]

  def get_validation_url do
    @validation_url
  end

  def sign(item) do
    if Tuist.Environment.dev?() or Tuist.Environment.test?() do
      nil
    else
      {:ok, %{signing_certificate: pem}} = get_license()
      [{_, der, _}] = :public_key.pem_decode(pem)
      key_size = byte_size(der) - 32
      <<_::binary-size(key_size), key::binary-size(32)>> = der

      signature = :crypto.sign(:eddsa, :none, JSON.encode!(item), [key, :ed25519])
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
             resolve_license(Tuist.Environment.get_license_key())
           end
         ) do
      {:ok, license} -> {:ok, license}
      {:error, error} -> {:error, error}
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
          base_64_signing_certificate =
            (payload["data"]["attributes"]["metadata"] || %{})["base64SigningCertificate"]

          signing_certificate =
            base_64_signing_certificate && Base.decode64!(base_64_signing_certificate)

          {:ok,
           %__MODULE__{
             valid: payload["meta"]["valid"],
             id: payload["data"]["id"],
             features: [],
             expiration_date: Timex.parse!(payload["data"]["attributes"]["expiry"], "{RFC3339}"),
             signing_certificate: signing_certificate
           }}
        end

      {:ok, %{status: status}} when status in 400..599 ->
        {:error, "The server to validate the license responded with a #{status} status code."}

      {:error, error} ->
        {:error, inspect(error)}
    end
  end
end
