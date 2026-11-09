defmodule Tuist.EntireTrails.Summary do
  @moduledoc false
  use Ecto.Schema

  @primary_key {:id, UUIDv7, autogenerate: true}
  @foreign_key_type UUIDv7
  schema "entire_trail_reports" do
    belongs_to :connection, Tuist.EntireTrails.Connection
    field :trail_id, :string
    field :head_sha, :string
    field :report_body, :string
    field :reported_at, :utc_datetime_usec
    field :published_at, :utc_datetime_usec
    field :publication_started, :boolean, default: false
    field :findings, {:array, :map}, default: []
    field :review_id, :string
    field :finding_ids, {:array, :string}, default: []
    timestamps(type: :utc_datetime)
  end
end
