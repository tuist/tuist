defmodule Atlas.Finance.SyncRun do
  use Atlas.Schema

  import Ecto.Changeset

  alias Atlas.Finance.Source

  schema "finance_sync_runs" do
    field :status, :string
    field :started_at, :utc_datetime
    field :finished_at, :utc_datetime
    field :accounts_seen, :integer, default: 0
    field :transactions_seen, :integer, default: 0
    field :error, :string
    field :metadata, :map, default: %{}

    belongs_to :source, Source, foreign_key: :finance_source_id

    timestamps(updated_at: false)
  end

  def changeset(sync_run, attrs) do
    sync_run
    |> cast(attrs, [
      :finance_source_id,
      :status,
      :started_at,
      :finished_at,
      :accounts_seen,
      :transactions_seen,
      :error,
      :metadata
    ])
    |> validate_required([:finance_source_id, :status, :started_at])
    |> validate_number(:accounts_seen, greater_than_or_equal_to: 0)
    |> validate_number(:transactions_seen, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:finance_source_id)
  end
end
