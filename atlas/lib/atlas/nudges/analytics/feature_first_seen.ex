defmodule Atlas.Nudges.Analytics.FeatureFirstSeen do
  @moduledoc """
  Per-(account, feature) marker of the first time we detected activity for
  that feature on that account. Populated once by
  `Atlas.Nudges.Workers.RefreshFeatureFirstSeen`; never updated after
  insertion.

  The four "first X event" signals (`first_cache_event`,
  `first_build_event`, `first_test_event`) fire off the insertion of a
  row here; `activation_stalled` fires when a candidate account has been
  around long enough and no row of any feature exists.
  """

  use Atlas.Schema

  import Ecto.Changeset

  alias Atlas.Accounts.Account

  schema "nudge_account_feature_first_seen" do
    field :feature, :string
    field :first_use_at, :utc_datetime
    field :first_seen_computed_at, :utc_datetime

    belongs_to :account, Account

    timestamps()
  end

  def changeset(record, attrs) do
    record
    |> cast(attrs, [:account_id, :feature, :first_use_at, :first_seen_computed_at])
    |> validate_required([:account_id, :feature, :first_use_at, :first_seen_computed_at])
    |> foreign_key_constraint(:account_id)
    |> unique_constraint([:account_id, :feature])
  end
end
