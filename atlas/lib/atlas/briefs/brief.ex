defmodule Atlas.Briefs.Brief do
  use Atlas.Schema

  import Ecto.Changeset

  alias Atlas.Briefs.BriefItem
  alias Atlas.Briefs.Subscription

  @cadences ~w(daily weekly monthly)
  @statuses ~w(draft material immaterial posted failed)
  @sensitivities ~w(public internal restricted)
  @generation_modes ~w(agent deterministic_fallback deterministic)

  @derive {
    Flop.Schema,
    filterable: [:cadence, :status, :brief_subscription_id],
    sortable: [:period_start, :inserted_at],
    default_limit: 25,
    max_limit: 100
  }

  schema "briefs" do
    field :cadence, :string
    field :period_start, :utc_datetime
    field :period_end, :utc_datetime
    field :status, :string, default: "draft"
    field :headline, :string
    field :summary, :string
    field :report, :map, default: %{}
    field :attention_budget, :integer
    field :sensitivity, :string, default: "internal"
    field :generated_by_agent, :string
    field :generation_mode, :string
    field :slack_channel_id, :string
    field :slack_thread_ts, :string
    field :posted_at, :utc_datetime
    field :failure_reason, :string

    belongs_to :subscription, Subscription, foreign_key: :brief_subscription_id
    has_many :items, BriefItem

    timestamps()
  end

  def cadences, do: @cadences
  def statuses, do: @statuses

  def changeset(brief, attrs) do
    brief
    |> cast(attrs, [
      :brief_subscription_id,
      :cadence,
      :period_start,
      :period_end,
      :status,
      :headline,
      :summary,
      :report,
      :attention_budget,
      :sensitivity,
      :generated_by_agent,
      :generation_mode,
      :slack_channel_id,
      :slack_thread_ts,
      :posted_at,
      :failure_reason
    ])
    |> normalize_strings()
    |> validate_required([
      :brief_subscription_id,
      :cadence,
      :period_start,
      :period_end,
      :status,
      :attention_budget,
      :sensitivity
    ])
    |> validate_inclusion(:cadence, @cadences)
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:sensitivity, @sensitivities)
    |> validate_optional_inclusion(:generation_mode, @generation_modes)
    |> validate_number(:attention_budget, greater_than: 0, less_than_or_equal_to: 20)
    |> validate_period()
    |> foreign_key_constraint(:brief_subscription_id)
    |> unique_constraint([:brief_subscription_id, :cadence, :period_start])
    |> check_constraint(:cadence, name: :briefs_cadence_check)
    |> check_constraint(:status, name: :briefs_status_check)
    |> check_constraint(:generation_mode, name: :briefs_generation_mode_check)
    |> check_constraint(:sensitivity, name: :briefs_sensitivity_check)
    |> check_constraint(:attention_budget, name: :briefs_attention_budget_check)
  end

  defp validate_optional_inclusion(changeset, field, values) do
    if get_field(changeset, field), do: validate_inclusion(changeset, field, values), else: changeset
  end

  defp validate_period(changeset) do
    case {get_field(changeset, :period_start), get_field(changeset, :period_end)} do
      {%DateTime{} = start_at, %DateTime{} = end_at} ->
        if DateTime.before?(start_at, end_at),
          do: changeset,
          else: add_error(changeset, :period_end, "must be after the period start")

      _period ->
        changeset
    end
  end

  defp normalize_strings(changeset) do
    Enum.reduce(
      [
        :cadence,
        :status,
        :headline,
        :summary,
        :sensitivity,
        :generated_by_agent,
        :generation_mode,
        :slack_channel_id,
        :slack_thread_ts,
        :failure_reason
      ],
      changeset,
      fn field, changeset -> update_change(changeset, field, &normalize_string/1) end
    )
  end

  defp normalize_string(nil), do: nil

  defp normalize_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_string(value), do: value
end
