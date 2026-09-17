defmodule Atlas.Inference.Provider do
  @moduledoc """
  Runtime-managed upstream provider for the inference relay.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Plug.Crypto.KeyGenerator
  alias Plug.Crypto.MessageEncryptor

  @key_format ~r/^[A-Za-z0-9][A-Za-z0-9._:-]*$/
  @primary_key {:id, :binary_id, autogenerate: true}

  schema "inference_providers" do
    field :key, :string
    field :base_url, :string
    field :api_key_ciphertext, :string, redact: true
    field :api_key, :string, virtual: true, redact: true
    field :timeout, :integer, default: 300_000

    timestamps(type: :utc_datetime)
  end

  def changeset(provider, attrs) do
    provider
    |> cast(attrs, [:key, :base_url, :api_key, :timeout])
    |> normalize_strings([:key, :base_url, :api_key])
    |> validate_required([:key, :base_url, :timeout])
    |> validate_format(:key, @key_format)
    |> validate_number(:timeout, greater_than: 0)
    |> validate_base_url()
    |> put_encrypted_api_key()
    |> unique_constraint(:key)
  end

  def api_key(%__MODULE__{api_key_ciphertext: nil}), do: nil

  def api_key(%__MODULE__{api_key_ciphertext: ciphertext}) when is_binary(ciphertext) do
    with {encryption_key, signing_key} <- encryption_keys(),
         {:ok, api_key} <-
           MessageEncryptor.decrypt(ciphertext, encryption_key, signing_key) do
      api_key
    else
      _error -> nil
    end
  end

  def credential_configured?(%__MODULE__{api_key_ciphertext: value}) do
    is_binary(value) and String.trim(value) != ""
  end

  defp normalize_strings(changeset, fields) do
    Enum.reduce(fields, changeset, fn field, changeset ->
      update_change(changeset, field, &normalize_string/1)
    end)
  end

  defp normalize_string(nil), do: nil

  defp normalize_string(value) when is_binary(value) do
    value
    |> String.trim()
    |> case do
      "" -> nil
      value -> value
    end
  end

  defp normalize_string(value), do: value

  defp validate_base_url(changeset) do
    validate_change(changeset, :base_url, fn :base_url, value ->
      case URI.parse(value) do
        %URI{scheme: scheme, host: host} when scheme in ["http", "https"] and is_binary(host) ->
          []

        _uri ->
          [base_url: "must start with http:// or https:// and include a host"]
      end
    end)
  end

  defp put_encrypted_api_key(changeset) do
    case get_change(changeset, :api_key) do
      api_key when is_binary(api_key) and api_key != "" ->
        {encryption_key, signing_key} = encryption_keys()

        put_change(
          changeset,
          :api_key_ciphertext,
          MessageEncryptor.encrypt(api_key, encryption_key, signing_key)
        )

      _api_key ->
        changeset
    end
  end

  defp encryption_keys do
    secret_key_base = AtlasWeb.Endpoint.config(:secret_key_base)

    {
      KeyGenerator.generate(
        secret_key_base,
        "atlas inference provider credential encryption",
        length: 32
      ),
      KeyGenerator.generate(
        secret_key_base,
        "atlas inference provider credential signing",
        length: 32
      )
    }
  end
end
