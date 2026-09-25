defmodule Atlas.Accounts.POCs.Context do
  use Atlas.Schema

  import Ecto.Changeset

  alias Atlas.Accounts.POCs.POC

  @ci_solutions ~w(github_actions gitlab_ci buildkite circleci jenkins bitrise xcode_cloud namespace self_hosted other unknown)
  @git_forges ~w(github gitlab bitbucket azure_devops self_hosted other unknown)
  @primary_languages ~w(swift objective_c kotlin java react_native flutter mixed other unknown)

  schema "poc_contexts" do
    field :developer_count, :integer
    field :ci_solution, :string
    field :git_forge, :string
    field :primary_language, :string
    field :monorepo, :boolean
    field :notes, :string

    belongs_to :poc, POC

    timestamps(type: :utc_datetime)
  end

  def ci_solutions, do: @ci_solutions
  def git_forges, do: @git_forges
  def primary_languages, do: @primary_languages

  def changeset(context, attrs) do
    context
    |> cast(attrs, [
      :poc_id,
      :developer_count,
      :ci_solution,
      :git_forge,
      :primary_language,
      :monorepo,
      :notes
    ])
    |> validate_number(:developer_count, greater_than_or_equal_to: 0, less_than: 1_000_000)
    |> validate_inclusion(:ci_solution, @ci_solutions)
    |> validate_inclusion(:git_forge, @git_forges)
    |> validate_inclusion(:primary_language, @primary_languages)
    |> validate_length(:notes, max: 8000)
    |> unique_constraint(:poc_id)
  end
end
