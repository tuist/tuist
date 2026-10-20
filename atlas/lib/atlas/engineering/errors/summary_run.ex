defmodule Atlas.Engineering.Errors.SummaryRun do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @statuses [:generating, :generated, :delivered, :empty, :failed]

  schema "error_summary_runs" do
    field :scheduled_for, :utc_datetime
    field :window_start, :utc_datetime
    field :window_end, :utc_datetime
    field :input_fingerprint, :string
    field :issue_ids, {:array, Ecto.UUID}, default: []
    field :issue_count, :integer, default: 0
    field :status, Ecto.Enum, values: @statuses
    field :summary, :string
    field :attention, {:array, :map}, default: []
    field :slack_channel_id, :string
    field :slack_message_ts, :string
    field :generated_at, :utc_datetime
    field :delivered_at, :utc_datetime
    field :failure_reason, :string

    timestamps(type: :utc_datetime)
  end

  def changeset(run, attrs) do
    run
    |> cast(attrs, [
      :scheduled_for,
      :window_start,
      :window_end,
      :input_fingerprint,
      :issue_ids,
      :issue_count,
      :status,
      :summary,
      :attention,
      :slack_channel_id,
      :slack_message_ts,
      :generated_at,
      :delivered_at,
      :failure_reason
    ])
    |> validate_required([
      :scheduled_for,
      :window_start,
      :window_end,
      :input_fingerprint,
      :issue_ids,
      :issue_count,
      :status,
      :slack_channel_id
    ])
    |> validate_inclusion(:status, @statuses)
    |> validate_length(:input_fingerprint, is: 64)
    |> validate_number(:issue_count, greater_than_or_equal_to: 0)
    |> validate_length(:summary, max: 3_000)
    |> validate_length(:failure_reason, max: 500)
    |> unique_constraint(:scheduled_for)
  end
end
