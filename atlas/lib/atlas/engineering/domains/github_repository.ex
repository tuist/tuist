defmodule Atlas.Engineering.Domains.GitHubRepository do
  @moduledoc """
  A GitHub repository connected to an engineering project.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Atlas.Engineering.Projects.Project

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @visibilities [:public, :private]

  schema "engineering_github_repositories" do
    field :owner, :string
    field :name, :string
    field :visibility, Ecto.Enum, values: @visibilities, default: :public

    belongs_to :project, Project

    timestamps(type: :utc_datetime)
  end

  def visibilities, do: @visibilities

  def changeset(repository, attrs) do
    repository
    |> cast(attrs, [:owner, :name, :visibility, :project_id])
    |> normalize_string(:owner)
    |> normalize_string(:name)
    |> validate_required([:owner, :name, :visibility])
    |> validate_length(:owner, max: 39)
    |> validate_length(:name, max: 100)
    |> validate_format(:owner, ~r/^[a-z0-9][a-z0-9-]*[a-z0-9]$|^[a-z0-9]$/, message: "must be a valid GitHub owner")
    |> validate_format(:name, ~r/^[a-z0-9._-]+$/, message: "must be a valid GitHub repository name")
    |> validate_inclusion(:visibility, @visibilities)
    |> unique_constraint([:owner, :name])
    |> foreign_key_constraint(:project_id)
  end

  def full_name(repository), do: "#{repository.owner}/#{repository.name}"

  defp normalize_string(changeset, field) do
    update_change(changeset, field, fn
      value when is_binary(value) ->
        value
        |> String.trim()
        |> String.downcase()

      value ->
        value
    end)
  end
end
