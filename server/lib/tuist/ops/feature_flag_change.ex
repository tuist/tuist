defmodule Tuist.Ops.FeatureFlagChange do
  @moduledoc false
  use Ecto.Schema

  schema "feature_flag_changes" do
    field :change_id, Ecto.UUID
    field :flag_name, :string
    field :request, :map
    field :principal, :map
    field :before, :map
    field :after, :map
    timestamps(type: :utc_datetime, updated_at: false)
  end
end
