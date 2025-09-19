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
