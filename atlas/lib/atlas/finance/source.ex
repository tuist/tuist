defmodule Atlas.Finance.Source do
  use Atlas.Schema

  import Ecto.Changeset

  alias Atlas.Accounts.Account, as: AtlasAccount
  alias Atlas.Finance.Account
  alias Atlas.Finance.SyncRun

  schema "finance_sources" do
    field :provider, :string
    field :config_key, :string
    field :name, :string
    field :external_id, :string
    field :last_synced_at, :utc_datetime
    field :last_successful_sync_at, :utc_datetime
    field :last_error, :string
    field :metadata, :map, default: %{}

    belongs_to :atlas_account, AtlasAccount
    has_many :accounts, Account, foreign_key: :finance_source_id
    has_many :sync_runs, SyncRun, foreign_key: :finance_source_id

    timestamps()
  end

  def changeset(source, attrs) do
    source
    |> cast(attrs, [
      :atlas_account_id,
      :provider,
      :config_key,
      :name,
      :external_id,
      :last_synced_at,
      :last_successful_sync_at,
      :last_error,
      :metadata
    ])
    |> validate_required([:provider, :config_key, :name])
    |> update_change(:provider, &normalize_string/1)
    |> update_change(:config_key, &normalize_string/1)
    |> update_change(:name, &normalize_string/1)
    |> unique_constraint(:config_key)
    |> foreign_key_constraint(:atlas_account_id)
  end

  defp normalize_string(value) when is_binary(value), do: String.trim(value)
  defp normalize_string(value), do: value
end
