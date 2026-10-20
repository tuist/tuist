defmodule Atlas.Inference.Token do
  @moduledoc """
  Hashed bearer token bound to one inference model binding.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Atlas.Inference.ModelBinding
  alias Atlas.Inference.Usage
  alias Plug.Crypto.KeyGenerator
  alias Plug.Crypto.MessageEncryptor

  @atlas_roles ~w(inference coding embedding)
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "inference_tokens" do
    field :name, :string
    field :token_hash, :string, redact: true
    field :token_ciphertext, :string, redact: true
    field :atlas_role, :string
    field :enabled, :boolean, default: true
    field :expires_at, :utc_datetime
    field :last_used_at, :utc_datetime

    belongs_to :model_binding, ModelBinding
    has_many :usages, Usage

    timestamps(type: :utc_datetime)
  end

  def changeset(token, attrs) do
    token
    |> cast(attrs, [:name, :token_hash, :enabled, :expires_at, :last_used_at])
    |> update_change(:name, &normalize_name/1)
    |> validate_required([:name, :token_hash])
    |> unique_constraint(:token_hash)
    |> foreign_key_constraint(:model_binding_id)
  end

  def atlas_changeset(token, attrs) do
    token
    |> changeset(attrs)
    |> cast(attrs, [:atlas_role, :token_ciphertext])
    |> validate_required([:atlas_role, :token_ciphertext])
    |> validate_inclusion(:atlas_role, @atlas_roles)
    |> unique_constraint(:atlas_role, name: :inference_tokens_model_binding_atlas_role_index)
  end

  def encrypt_value(value) when is_binary(value) do
    {encryption_key, signing_key} = encryption_keys()
    MessageEncryptor.encrypt(value, encryption_key, signing_key)
  end

  def value(%__MODULE__{token_ciphertext: nil}), do: nil

  def value(%__MODULE__{token_ciphertext: ciphertext}) when is_binary(ciphertext) do
    with {encryption_key, signing_key} <- encryption_keys(),
         {:ok, value} <-
           MessageEncryptor.decrypt(ciphertext, encryption_key, signing_key) do
      value
    else
      _error -> nil
    end
  end

  defp normalize_name(nil), do: nil

  defp normalize_name(value) when is_binary(value) do
    value
    |> String.trim()
    |> case do
      "" -> nil
      value -> value
    end
  end

  defp normalize_name(value), do: value

  defp encryption_keys do
    secret_key_base = AtlasWeb.Endpoint.config(:secret_key_base)

    {
      KeyGenerator.generate(
        secret_key_base,
        "atlas inference token value encryption",
        length: 32
      ),
      KeyGenerator.generate(
        secret_key_base,
        "atlas inference token value signing",
        length: 32
      )
    }
  end
end
