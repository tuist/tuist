defmodule Tuist.IdempotentRequests.Claim do
  @moduledoc false

  use Ecto.Schema

  @primary_key false
  schema "idempotent_requests" do
    field :project_id, :integer, primary_key: true
    field :kind, :string, primary_key: true
    field :request_id, Ecto.UUID, primary_key: true
    field :lease_id, Ecto.UUID
    field :claimed_at, :utc_datetime
    field :completed_at, :utc_datetime
    field :result, :binary

    timestamps(type: :utc_datetime)
  end
end
