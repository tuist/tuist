defmodule Tuist.Ops.AccountPlanChange do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Changeset

  schema "account_plan_changes" do
    field :change_id, Ecto.UUID
    field :account_id, :integer
    field :request, :map
    field :principal, :map
    field :before, :map
    field :after, :map
    timestamps(type: :utc_datetime, updated_at: false)
  end

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:change_id, :account_id, :request, :principal, :before, :after])
    |> validate_required([:change_id, :account_id, :request, :principal, :before, :after])
    |> unique_constraint(:change_id)
  end
end
