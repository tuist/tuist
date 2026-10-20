defmodule Atlas.Licenses.License do
  use Atlas.Schema

  import Ecto.Changeset

  alias Atlas.Accounts.Account
  alias Atlas.Encrypted.Binary

  @derive {
    Flop.Schema,
    filterable: [:account_id], sortable: [:expires_on, :inserted_at], default_limit: 100, max_limit: 100
  }

  schema "licenses" do
    field :key, Binary
    field :key_hash, :binary
    field :signing_key, Binary
    field :expires_on, :date

    belongs_to :account, Account

    timestamps()
  end

  def request_changeset(license, attrs) do
    license
    |> cast(attrs, [:account_id, :expires_on])
    |> validate_required([:account_id, :expires_on])
    |> validate_expiration_date()
    |> foreign_key_constraint(:account_id)
  end

  def issued_changeset(license, attrs) do
    license
    |> cast(attrs, [:account_id, :key, :key_hash, :signing_key, :expires_on])
    |> validate_required([:account_id, :key, :key_hash, :signing_key, :expires_on])
    |> unique_constraint(:key_hash)
    |> foreign_key_constraint(:account_id)
  end

  def extension_changeset(license, attrs) do
    license
    |> cast(attrs, [:expires_on])
    |> validate_required([:expires_on])
    |> validate_expiration_date()
    |> validate_extension(license.expires_on)
  end

  defp validate_expiration_date(changeset) do
    validate_change(changeset, :expires_on, fn :expires_on, expires_on ->
      if Date.before?(expires_on, Date.utc_today()) do
        [expires_on: "must be today or later"]
      else
        []
      end
    end)
  end

  defp validate_extension(changeset, current_expiration_date) do
    case get_field(changeset, :expires_on) do
      %Date{} = expires_on when not is_nil(current_expiration_date) ->
        if Date.after?(expires_on, current_expiration_date) do
          changeset
        else
          add_error(changeset, :expires_on, "must be after the current expiration date")
        end

      _other ->
        changeset
    end
  end
end
