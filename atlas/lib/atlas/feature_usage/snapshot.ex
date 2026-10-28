defmodule Atlas.FeatureUsage.Snapshot do
  @moduledoc """
  A point-in-time measurement of how much a single account used a single Tuist
  feature, bucketed into the last-24h, last-7d, and prior-7d windows.

  `active` / `active_previous` are derived flags: `active` means the feature saw
  usage in the last 7 days, `active_previous` in the 7 days before that. The
  active -> inactive transition is what drives the "stopped using a feature"
  Slack alert.
  """

  use Atlas.Schema

  import Ecto.Changeset

  alias Atlas.Accounts.Account
  alias Atlas.FeatureUsage.Catalog

  @fields [
    :account_id,
    :feature,
    :events_last_24h,
    :events_last_7d,
    :events_prior_7d,
    :last_used_at,
    :active,
    :active_previous,
    :computed_at
  ]

  schema "feature_usage_snapshots" do
    field :feature, :string
    field :events_last_24h, :integer, default: 0
    field :events_last_7d, :integer, default: 0
    field :events_prior_7d, :integer, default: 0
    field :last_used_at, :utc_datetime
    field :active, :boolean, default: false
    field :active_previous, :boolean, default: false
    field :computed_at, :utc_datetime

    belongs_to :account, Account

    timestamps()
  end

  def changeset(snapshot, attrs) do
    snapshot
    |> cast(attrs, @fields)
    |> validate_required([
      :account_id,
      :feature,
      :events_last_24h,
      :events_last_7d,
      :events_prior_7d,
      :active,
      :active_previous,
      :computed_at
    ])
    |> validate_inclusion(:feature, Catalog.all_slugs())
    |> foreign_key_constraint(:account_id)
    |> unique_constraint([:account_id, :feature, :computed_at],
      name: :feature_usage_snapshots_account_feature_computed_at_index
    )
  end
end
