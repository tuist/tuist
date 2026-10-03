defmodule Atlas.Accounts.OutcomeProposal do
  use Atlas.Schema

  import Ecto.Changeset

  alias Atlas.Accounts.Account
  alias Atlas.Accounts.Event
  alias Atlas.Accounts.Outcome
  alias Atlas.Users.User

  @proposal_types ~w(new_outcome outcome_review)
  @statuses ~w(pending approved rejected)

  schema "account_outcome_proposals" do
    field :proposal_type, :string
    field :status, :string, default: "pending"
    field :proposal_key, :string
    field :title, :string
    field :description, :string
    field :motion, :string
    field :success_measure, :string
    field :baseline, :string
    field :target, :string
    field :target_date, :date
    field :health, :string
    field :summary, :string
    field :recommendation, :string
    field :evidence, :map, default: %{"items" => []}
    field :confidence, :decimal
    field :rationale, :string
    field :generated_by_agent, :string
    field :reviewed_at, :utc_datetime
    field :rejection_reason, :string
    field :metadata, :map, default: %{}

    belongs_to :account, Account
    belongs_to :outcome, Outcome
    belongs_to :source_event, Event
    belongs_to :reviewed_by, User

    timestamps()
  end

  def proposal_types, do: @proposal_types
  def statuses, do: @statuses

  def changeset(proposal, attrs) do
    proposal
    |> cast(attrs, [
      :proposal_type,
      :status,
      :proposal_key,
      :title,
      :description,
      :motion,
      :success_measure,
      :baseline,
      :target,
      :target_date,
      :health,
      :summary,
      :recommendation,
      :evidence,
      :confidence,
      :rationale,
      :generated_by_agent,
      :metadata
    ])
    |> normalize_string_fields()
    |> validate_required([
      :account_id,
      :proposal_type,
      :status,
      :proposal_key,
      :confidence,
      :rationale,
      :generated_by_agent
    ])
    |> validate_inclusion(:proposal_type, @proposal_types)
    |> validate_inclusion(:status, @statuses)
    |> validate_number(:confidence, greater_than_or_equal_to: 0, less_than_or_equal_to: 1)
    |> validate_evidence()
    |> validate_proposal_fields()
    |> unique_constraint(:proposal_key, name: :account_outcome_proposals_pending_key_index)
    |> check_constraint(:motion, name: :account_outcome_proposals_motion_check)
    |> check_constraint(:health, name: :account_outcome_proposals_health_check)
    |> check_constraint(:proposal_type, name: :account_outcome_proposals_shape_check)
    |> foreign_key_constraint(:account_id)
    |> foreign_key_constraint(:outcome_id)
    |> foreign_key_constraint(:source_event_id)
    |> unique_constraint(:proposal_key, name: :account_outcome_proposals_pending_key_index)
    |> check_constraint(:proposal_type, name: :account_outcome_proposals_type_check)
    |> check_constraint(:status, name: :account_outcome_proposals_status_check)
    |> check_constraint(:motion, name: :account_outcome_proposals_motion_check)
    |> check_constraint(:health, name: :account_outcome_proposals_health_check)
    |> check_constraint(:confidence, name: :account_outcome_proposals_confidence_check)
    |> check_constraint(:proposal_type, name: :account_outcome_proposals_shape_check)
  end

  def edit_changeset(%__MODULE__{status: "pending"} = proposal, attrs) do
    proposal
    |> cast(attrs, editable_fields(proposal.proposal_type))
    |> normalize_string_fields()
    |> validate_evidence()
    |> validate_proposal_fields()
  end

  def edit_changeset(proposal, _attrs) do
    proposal
    |> change()
    |> add_error(:status, "must be pending")
  end

  def decision_changeset(%__MODULE__{status: "pending"} = proposal, attrs) do
    proposal
    |> cast(attrs, [:status, :reviewed_at, :rejection_reason])
    |> normalize_string_fields()
    |> validate_required([:status, :reviewed_at])
    |> validate_inclusion(:status, ~w(approved rejected))
    |> validate_rejection_reason()
  end

  def decision_changeset(proposal, _attrs) do
    proposal
    |> change()
    |> add_error(:status, "must be pending")
  end

  def proposal_key("outcome_review", outcome_id, _attrs) when is_binary(outcome_id) do
    "outcome_review:#{outcome_id}"
  end

  def proposal_key("new_outcome", _outcome_id, attrs) do
    title = normalized_key_value(value(attrs, "title"))
    motion = normalized_key_value(value(attrs, "motion"))
    "new_outcome:#{motion}:#{title}"
  end

  def proposal_key(_proposal_type, _outcome_id, _attrs), do: nil

  defp editable_fields("outcome_review"), do: [:health, :summary, :recommendation, :evidence, :rationale]

  defp editable_fields(_proposal_type) do
    [:title, :description, :motion, :success_measure, :baseline, :target, :target_date, :evidence, :rationale]
  end

  defp validate_proposal_fields(changeset) do
    case get_field(changeset, :proposal_type) do
      "new_outcome" ->
        changeset
        |> validate_required([:title, :motion])
        |> validate_inclusion(:motion, Outcome.motions())

      "outcome_review" ->
        changeset
        |> validate_required([:outcome_id, :health, :summary])
        |> validate_inclusion(:health, Outcome.health_values())

      _proposal_type ->
        changeset
    end
  end

  defp validate_evidence(changeset) do
    case get_field(changeset, :evidence) do
      %{"items" => items} when is_list(items) and items != [] -> changeset
      %{"items" => []} -> add_error(changeset, :evidence, "must include at least one item")
      %{} -> add_error(changeset, :evidence, "must include an items list")
      _other -> add_error(changeset, :evidence, "must be a map")
    end
  end

  defp validate_rejection_reason(changeset) do
    if get_field(changeset, :status) == "rejected" do
      validate_required(changeset, [:rejection_reason])
    else
      changeset
    end
  end

  defp normalize_string_fields(changeset) do
    Enum.reduce(
      [
        :title,
        :description,
        :success_measure,
        :baseline,
        :target,
        :summary,
        :recommendation,
        :rationale,
        :generated_by_agent,
        :rejection_reason
      ],
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

  defp normalized_key_value(nil), do: ""

  defp normalized_key_value(value) do
    value
    |> to_string()
    |> String.trim()
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/u, "-")
    |> String.trim("-")
  end

  defp value(attrs, key) when is_map(attrs) do
    Enum.find_value(attrs, fn {candidate_key, value} ->
      if to_string(candidate_key) == key, do: value
    end)
  end
end
