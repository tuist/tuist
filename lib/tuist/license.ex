defmodule Tuist.License do
  @moduledoc ~S"""
  Interface to check the environment licenses.
  """

  alias Tuist.KeyValueStore

  require Logger

  @validation_url "https://api.keygen.sh/v1/accounts/cce51171-9339-4430-8441-73bb5abd9a5c/licenses/actions/validate-key"

  @enforce_keys [:id, :features, :expiration_date, :valid]
  defstruct [:id, :features, :expiration_date, :valid]

  def get_validation_url do
    @validation_url
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

    case {Tuist.Environment.on_premise?(), get_license(opts)} do
      {false, _} ->
        :ok

      {true, {:ok, %{valid: true}}} ->
        :ok

      {true, {:ok, nil}} ->
        raise "The license key exposed through the environment variable TUIST_LICENSE or TUIST_LICENSE_KEY is missing."

      {true, {:ok, %{valid: false}}} ->
        raise "The license key is invalid or expired. Please, conctact contact@tuist.io to get a new one."

      {true, {:error, error}} ->
        raise "The license validation failed with the following error: #{error}"
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
          {:ok,
           %__MODULE__{
             valid: payload["meta"]["valid"],
             id: payload["data"]["id"],
             features: [],
             expiration_date: Timex.parse!(payload["data"]["attributes"]["expiry"], "{RFC3339}")
           }}
        end

      {:ok, %{status: status}} when status in 400..599 ->
        {:error, "The server to validate the license responded with a #{status} status code."}

      {:error, error} ->
        {:error, inspect(error)}
    end
  end
end
