defmodule Tuist.OIDC.ScopeRule do
  @moduledoc """
  A rule that an OIDC-exchanged token must satisfy to carry a write scope.

  A rule belongs to either a project, gating a `project:*` scope for it, or an
  account, gating an `account:*` scope for it; never both. Each field is a list
  of patterns matched against the corresponding GitHub Actions claim; an empty
  field is unconstrained, but at least one field must be set.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Accounts.Account
  alias Tuist.Projects.Project

  @project_scopes [
    "project:cache:write",
    "project:previews:write",
    "project:bundles:write",
    "project:tests:write",
    "project:builds:write",
    "project:runs:write"
  ]

  @account_scopes ["account:cache:write"]

  @fields [:refs, :job_workflow_refs, :environments]
  @max_patterns 20
  @max_pattern_length 255

  @primary_key {:id, UUIDv7, autogenerate: true}
  schema "oidc_scope_rules" do
    field :scope, :string
    field :refs, {:array, :string}, default: []
    field :job_workflow_refs, {:array, :string}, default: []
    field :environments, {:array, :string}, default: []

    belongs_to :account, Account
    belongs_to :project, Project

    timestamps(type: :utc_datetime)
  end

  def project_scopes, do: @project_scopes
  def account_scopes, do: @account_scopes
  def fields, do: @fields

  def changeset(rule \\ %__MODULE__{}, attrs) do
    rule
    |> cast(attrs, [:account_id, :project_id, :scope | @fields])
    |> validate_required([:scope])
    |> validate_owner()
    |> update_change(:refs, &normalize_patterns/1)
    |> update_change(:job_workflow_refs, &normalize_patterns/1)
    |> update_change(:environments, &normalize_patterns/1)
    |> validate_scope_level()
    |> validate_patterns()
    |> validate_any_field_set()
    |> unique_constraint([:project_id, :scope], name: :oidc_scope_rules_project_id_scope_index)
    |> unique_constraint([:account_id, :scope], name: :oidc_scope_rules_account_id_scope_index)
    |> check_constraint(:scope, name: :oidc_scope_rules_scope_level)
    |> foreign_key_constraint(:account_id)
    |> foreign_key_constraint(:project_id)
  end

  defp normalize_patterns(patterns) do
    patterns
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp validate_owner(changeset) do
    case {get_field(changeset, :account_id), get_field(changeset, :project_id)} do
      {nil, nil} ->
        add_error(changeset, :scope, "must belong to a project or an account")

      {account_id, project_id} when not is_nil(account_id) and not is_nil(project_id) ->
        add_error(changeset, :scope, "can't belong to both a project and an account")

      _ ->
        changeset
    end
  end

  defp validate_scope_level(changeset) do
    scopes = if get_field(changeset, :project_id), do: @project_scopes, else: @account_scopes
    validate_inclusion(changeset, :scope, scopes)
  end

  defp validate_patterns(changeset) do
    Enum.reduce(@fields, changeset, fn field, changeset ->
      changeset
      |> validate_length(field, max: @max_patterns)
      |> validate_change(field, fn field, patterns ->
        if Enum.any?(patterns, &(String.length(&1) > @max_pattern_length)) do
          [{field, "patterns must be at most #{@max_pattern_length} characters"}]
        else
          []
        end
      end)
    end)
  end

  defp validate_any_field_set(changeset) do
    if Enum.all?(@fields, &(get_field(changeset, &1) == [])) do
      add_error(changeset, :refs, "add at least one branch, workflow, or environment pattern")
    else
      changeset
    end
  end
end
