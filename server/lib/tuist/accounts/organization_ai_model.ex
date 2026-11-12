defmodule Tuist.Accounts.OrganizationAIModel do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Accounts.Organization
  alias Tuist.Accounts.OrganizationAIConnection

  schema "organization_ai_models" do
    belongs_to :organization, Organization
    belongs_to :connection, OrganizationAIConnection
    field :name, :string
    field :model_id, :string

    timestamps(type: :utc_datetime)
  end

  def changeset(model, attrs) do
    model
    |> cast(attrs, [:connection_id, :name, :model_id])
    |> update_change(:name, &(&1 && String.trim(&1)))
    |> update_change(:model_id, &(&1 && String.trim(&1)))
    |> validate_required([:organization_id, :connection_id, :name, :model_id])
    |> validate_number(:connection_id, greater_than: 0, less_than_or_equal_to: 9_223_372_036_854_775_807)
    |> validate_length(:name, max: 100)
    |> validate_length(:model_id, max: 200)
    |> validate_format(:model_id, ~r/\A[a-zA-Z0-9][a-zA-Z0-9._\/:\-]*\z/)
    |> unique_constraint([:connection_id, :model_id])
  end
end
