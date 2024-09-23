defmodule Tuist.License do
  @moduledoc ~S"""
  Interface to check the environment licenses.
  """

  @cache_key "license"
  @validation_url "https://api.keygen.sh/v1/accounts/cce51171-9339-4430-8441-73bb5abd9a5c/licenses/actions/validate-key"

  @enforce_keys [:id, :features, :expiration_date, :valid]
  defstruct [:id, :features, :expiration_date, :valid]

  def get_validation_url() do
    @validation_url
  end

  def get_license(opts \\ []) do
    cache = opts |> Keyword.get(:cache, :tuist)
    ttl = Keyword.get(opts, :ttl, :timer.hours(24))

    result =
      Cachex.fetch(cache, @cache_key, fn ->
        case resolve_license() do
          {:ok, license} -> {:commit, license, ttl: ttl}
          {:error, error} -> {:error, error}
        end
      end)

    case result do
      {:commit, license, _} -> {:ok, license}
      {:ok, license} -> {:ok, license}
      {:error, error} -> {:error, error}
    end
  end

  def assert_valid!(opts \\ []) do
    case {Tuist.Environment.on_premise?(), get_license(opts)} do
      {false, _} ->
        :ok

      {true, {:ok, %{valid: true}}} ->
        :ok

      {true, {:ok, nil}} ->
        raise "The license key exposed through the environment variable TUIST_LICENSE or TUIST_LICENSE_KEY is missing."

      {true, {:ok, %{valid: false}}} ->
        raise "The license key is invalid or expired. Please, conctact contact@tuist.io to get a new one."
    end
  end

  def resolve_license() do
    key = Tuist.Environment.get_license_key()

    if is_nil(key) do
      {:ok, nil}
    else
      url =
        "https://api.keygen.sh/v1/accounts/cce51171-9339-4430-8441-73bb5abd9a5c/licenses/actions/validate-key"

      payload = Req.post!(url, json: %{meta: %{key: key}}).body

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
    end
  end
end
