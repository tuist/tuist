defmodule Atlas.Accounts.OutcomeReview do
  use Atlas.Schema

  import Ecto.Changeset

  alias Atlas.Accounts.Outcome
  alias Atlas.Users.User

  schema "account_outcome_reviews" do
    field :health, :string
    field :summary, :string
    field :evidence, :map, default: %{"items" => []}
    field :recommendation, :string
    field :reviewed_at, :utc_datetime
    field :created_by_agent, :string
    field :metadata, :map, default: %{}

    belongs_to :outcome, Outcome
    belongs_to :author, User

    timestamps()
  end

  def changeset(review, attrs) do
    review
    |> cast(attrs, [
      :health,
      :summary,
      :evidence,
      :recommendation,
      :reviewed_at,
      :created_by_agent,
      :metadata
    ])
    |> validate_required([:outcome_id, :health, :summary, :reviewed_at])
    |> validate_inclusion(:health, Outcome.health_values())
    |> validate_evidence()
    |> normalize_string_fields()
    |> foreign_key_constraint(:outcome_id)
    |> foreign_key_constraint(:author_id)
  end

  defp validate_evidence(changeset) do
    case get_field(changeset, :evidence) do
      %{"items" => items} when is_list(items) -> changeset
      %{} -> add_error(changeset, :evidence, "must include an items list")
      _other -> add_error(changeset, :evidence, "must be a map")
    end
  end

  defp normalize_string_fields(changeset) do
    Enum.reduce([:summary, :recommendation, :created_by_agent], changeset, &normalize_string_field/2)
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
