defmodule Atlas.Briefs.BriefItem do
  use Atlas.Schema

  import Ecto.Changeset

  alias Atlas.Briefs.Brief
  alias Atlas.Users.User

  @domains ~w(finance accounts outreach product company)
  @kinds ~w(observation concern change risk follow_up expectation_missed proposal claim)
  @severities ~w(info warning critical)
  @sensitivities ~w(public internal restricted)
  @statuses ~w(open acknowledged completed dismissed suppressed expired)
  @usefulness_values ~w(useful not_useful)

  schema "brief_items" do
    field :domain, :string
    field :kind, :string
    field :title, :string
    field :detail, :string
    field :severity, :string
    field :sensitivity, :string
    field :materiality_score, :decimal
    field :confidence, :decimal
    field :suggested_action, :string
    field :completion_condition, :string
    field :fingerprint, :string
    field :source_type, :string
    field :source_id, Atlas.UUIDv7
    field :source_path, :string
    field :position, :integer
    field :status, :string, default: "open"
    field :due_at, :utc_datetime
    field :resolved_at, :utc_datetime
    field :resolution_note, :string
    field :usefulness, :string
    field :usefulness_reason, :string
    field :usefulness_at, :utc_datetime

    belongs_to :brief, Brief
    belongs_to :owner, User
    belongs_to :resolved_by, User
    belongs_to :usefulness_by, User

    timestamps()
  end

  def domains, do: @domains
  def kinds, do: @kinds
  def severities, do: @severities
  def statuses, do: @statuses

  def changeset(item, attrs) do
    item
    |> cast(attrs, [
      :brief_id,
      :domain,
      :kind,
      :title,
      :detail,
      :severity,
      :sensitivity,
      :materiality_score,
      :confidence,
      :suggested_action,
      :completion_condition,
      :fingerprint,
      :source_type,
      :source_id,
      :source_path,
      :position,
      :status,
      :owner_id,
      :due_at,
      :resolved_at,
      :resolved_by_id,
      :resolution_note,
      :usefulness,
      :usefulness_reason,
      :usefulness_at,
      :usefulness_by_id
    ])
    |> normalize_strings()
    |> validate_required([
      :brief_id,
      :domain,
      :kind,
      :title,
      :detail,
      :severity,
      :sensitivity,
      :materiality_score,
      :fingerprint,
      :position,
      :status
    ])
    |> validate_inclusion(:domain, @domains)
    |> validate_inclusion(:kind, @kinds)
    |> validate_inclusion(:severity, @severities)
    |> validate_inclusion(:sensitivity, @sensitivities)
    |> validate_inclusion(:status, @statuses)
    |> validate_optional_inclusion(:usefulness, @usefulness_values)
    |> validate_number(:materiality_score, greater_than_or_equal_to: 0, less_than_or_equal_to: 1)
    |> validate_number(:confidence, greater_than_or_equal_to: 0, less_than_or_equal_to: 1)
    |> validate_number(:position, greater_than_or_equal_to: 0)
    |> validate_resolution_shape()
    |> validate_usefulness_shape()
    |> foreign_key_constraint(:brief_id)
    |> foreign_key_constraint(:owner_id)
    |> foreign_key_constraint(:resolved_by_id)
    |> foreign_key_constraint(:usefulness_by_id)
    |> unique_constraint([:brief_id, :fingerprint])
    |> check_constraint(:domain, name: :brief_items_domain_check)
    |> check_constraint(:kind, name: :brief_items_kind_check)
    |> check_constraint(:severity, name: :brief_items_severity_check)
    |> check_constraint(:status, name: :brief_items_status_check)
    |> check_constraint(:usefulness, name: :brief_items_usefulness_check)
    |> check_constraint(:materiality_score, name: :brief_items_materiality_check)
    |> check_constraint(:confidence, name: :brief_items_confidence_check)
    |> check_constraint(:resolved_at, name: :brief_items_resolution_shape_check)
    |> check_constraint(:usefulness_at, name: :brief_items_usefulness_shape_check)
  end

  defp validate_optional_inclusion(changeset, field, values) do
    if get_field(changeset, field), do: validate_inclusion(changeset, field, values), else: changeset
  end

  defp validate_resolution_shape(changeset) do
    if get_field(changeset, :status) in ["completed", "dismissed"] and
         is_nil(get_field(changeset, :resolved_at)) do
      add_error(changeset, :resolved_at, "is required when resolving an item")
    else
      changeset
    end
  end

  defp validate_usefulness_shape(changeset) do
    case {get_field(changeset, :usefulness), get_field(changeset, :usefulness_at)} do
      {nil, nil} -> changeset
      {usefulness, %DateTime{}} when usefulness in @usefulness_values -> changeset
      {_usefulness, _at} -> add_error(changeset, :usefulness_at, "must be set with usefulness feedback")
    end
  end

  defp normalize_strings(changeset) do
    Enum.reduce(
      [
        :domain,
        :kind,
        :title,
        :detail,
        :severity,
        :sensitivity,
        :suggested_action,
        :completion_condition,
        :fingerprint,
        :source_type,
        :source_path,
        :status,
        :resolution_note,
        :usefulness,
        :usefulness_reason
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
