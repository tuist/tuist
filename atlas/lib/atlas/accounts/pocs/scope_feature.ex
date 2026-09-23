defmodule Atlas.Accounts.POCs.ScopeFeature do
  use Atlas.Schema

  import Ecto.Changeset

  alias Atlas.Accounts.FeatureInterest
  alias Atlas.Accounts.POCs.POC

  schema "poc_scope_features" do
    belongs_to :poc, POC
    belongs_to :feature_interest, FeatureInterest

    timestamps(type: :utc_datetime)
  end

  def changeset(scope_feature, attrs) do
    scope_feature
    |> cast(attrs, [:poc_id, :feature_interest_id])
    |> validate_required([:poc_id, :feature_interest_id])
    |> unique_constraint([:poc_id, :feature_interest_id],
      name: :poc_scope_features_poc_id_feature_interest_id_index
    )
    |> foreign_key_constraint(:poc_id)
    |> foreign_key_constraint(:feature_interest_id)
  end
end
