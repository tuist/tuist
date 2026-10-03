defmodule Atlas.Accounts.Outcome do
  use Atlas.Schema

  import Ecto.Changeset

  alias Atlas.Accounts.Account
  alias Atlas.Accounts.Event
  alias Atlas.Accounts.OutcomeReview
  alias Atlas.Users.User

  @statuses ~w(active achieved missed abandoned)
  @health_values ~w(unknown on_track at_risk off_track)
  @motions ~w(evaluation adoption expansion renewal recovery)

  @derive {
    Flop.Schema,
    filterable: [:status, :health, :account_id],
    sortable: [:target_date, :reviewed_at, :inserted_at],
    default_limit: 15,
    max_limit: 100
  }

  schema "account_outcomes" do
    field :status, :string, default: "active"
    field :health, :string, default: "unknown"
    field :motion, :string, default: "adoption"
    field :title, :string
    field :description, :string
    field :success_measure, :string
    field :baseline, :string
    field :target, :string
    field :target_date, :date
    field :reviewed_at, :utc_datetime
    field :achieved_at, :utc_datetime
    field :closed_at, :utc_datetime
    field :metadata, :map, default: %{}

    belongs_to :account, Account
    belongs_to :owner, User
    belongs_to :source_event, Event

    has_many :reviews, OutcomeReview

    timestamps()
  end

  def statuses, do: @statuses
  def health_values, do: @health_values
  def motions, do: @motions

  def changeset(outcome, attrs) do
    outcome
    |> cast(attrs, [
      :status,
      :health,
      :motion,
      :title,
      :description,
      :success_measure,
      :baseline,
      :target,
      :target_date,
      :reviewed_at,
      :achieved_at,
      :closed_at,
      :metadata
    ])
    |> validate_required([:account_id, :title, :status, :health, :motion])
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:health, @health_values)
    |> validate_inclusion(:motion, @motions)
    |> normalize_string_fields()
    |> foreign_key_constraint(:account_id)
    |> foreign_key_constraint(:owner_id)
    |> foreign_key_constraint(:source_event_id)
  end

  defp normalize_string_fields(changeset) do
    Enum.reduce(
      [:title, :description, :success_measure, :baseline, :target],
      changeset,
      &normalize_string_field/2
    )
  end

  defp normalize_string_field(field, changeset) do
    update_change(changeset, field, fn
      nil -> nil
      value when is_binary(value) -> normalize_string(value)
      value -> value
    end)
  end

  defp normalize_string(value) do
    case String.trim(value) do
      "" -> nil
      normalized -> normalized
    end
  end
end
