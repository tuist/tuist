defmodule Atlas.Evidence.Link do
  use Atlas.Schema

  import Ecto.Changeset

  @subject_types ~w(account_outcome_proposal account_outcome_review outreach_recommendation brief_item cross_domain_claim)
  @record_types ~w(account_event account_term finance_invoice finance_transaction account_outcome account_outcome_review outreach_message_attempt product_trace document audit_activity brief_item)
  @source_classes ~w(observed human_asserted agent_derived decided action_result)
  @sensitivities ~w(public internal restricted)

  schema "evidence_links" do
    field :subject_type, :string
    field :subject_id, Atlas.UUIDv7
    field :record_type, :string
    field :record_id, Atlas.UUIDv7
    field :source_class, :string
    field :sensitivity, :string, default: "internal"
    field :observation, :string
    field :occurred_at, :utc_datetime
    field :position, :integer, default: 0

    timestamps(updated_at: false)
  end

  def subject_types, do: @subject_types
  def record_types, do: @record_types
  def source_classes, do: @source_classes
  def sensitivities, do: @sensitivities

  def changeset(link, attrs) do
    link
    |> cast(attrs, [
      :subject_type,
      :subject_id,
      :record_type,
      :record_id,
      :source_class,
      :sensitivity,
      :observation,
      :occurred_at,
      :position
    ])
    |> normalize_strings()
    |> validate_required([
      :subject_type,
      :subject_id,
      :record_type,
      :record_id,
      :source_class,
      :sensitivity,
      :observation,
      :occurred_at,
      :position
    ])
    |> validate_inclusion(:subject_type, @subject_types)
    |> validate_inclusion(:record_type, @record_types)
    |> validate_inclusion(:source_class, @source_classes)
    |> validate_inclusion(:sensitivity, @sensitivities)
    |> validate_number(:position, greater_than_or_equal_to: 0)
    |> validate_not_self_reference()
    |> unique_constraint([:subject_type, :subject_id, :record_type, :record_id],
      name: :evidence_links_subject_type_subject_id_record_type_record_id_in
    )
    |> check_constraint(:source_class, name: :evidence_links_source_class_check)
    |> check_constraint(:sensitivity, name: :evidence_links_sensitivity_check)
    |> check_constraint(:subject_type, name: :evidence_links_subject_type_check)
    |> check_constraint(:record_type, name: :evidence_links_record_type_check)
    |> check_constraint(:subject_id, name: :evidence_links_no_self_reference_check)
  end

  defp normalize_strings(changeset) do
    Enum.reduce(
      [:subject_type, :record_type, :source_class, :sensitivity, :observation],
      changeset,
      fn field, changeset ->
        update_change(changeset, field, fn
          nil -> nil
          value when is_binary(value) -> value |> String.trim() |> empty_to_nil()
          value -> value
        end)
      end
    )
  end

  defp validate_not_self_reference(changeset) do
    if get_field(changeset, :subject_type) == get_field(changeset, :record_type) and
         get_field(changeset, :subject_id) == get_field(changeset, :record_id) do
      add_error(changeset, :record_id, "cannot cite itself")
    else
      changeset
    end
  end

  defp empty_to_nil(""), do: nil
  defp empty_to_nil(value), do: value
end
