defmodule Atlas.Engineering.Domains.Domain do
  @moduledoc """
  A domain is a reusable tag an operator wants to slice engineering
  surfaces by, for example "Cache" or "Generated projects". A domain may be
  associated with more than one project.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Atlas.Engineering.Projects.Project
  alias Atlas.Engineering.Projects.ProjectDomain

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @visibilities [:public, :private]

  schema "domains" do
    field :name, :string
    field :description, :string
    field :visibility, Ecto.Enum, values: @visibilities, default: :public

    field :github_repository_owner, :string, virtual: true
    field :github_repository_name, :string, virtual: true
    field :github_repository_visibility, Ecto.Enum, values: [:public, :private], virtual: true
    field :project_id, :binary_id, virtual: true

    many_to_many :projects, Project,
      join_through: ProjectDomain,
      join_keys: [domain_id: :id, project_id: :id]

    timestamps(type: :utc_datetime)
  end

  def visibilities, do: @visibilities

  def changeset(domain, attrs) do
    domain
    |> cast(attrs, [
      :name,
      :description,
      :visibility,
      :project_id,
      :github_repository_owner,
      :github_repository_name,
      :github_repository_visibility
    ])
    |> normalize_string(:name)
    |> normalize_string(:description)
    |> normalize_string(:github_repository_owner, &String.downcase/1)
    |> normalize_string(:github_repository_name, &String.downcase/1)
    |> validate_required([:name, :visibility])
    |> validate_length(:name, max: 120)
    |> validate_length(:description, max: 500)
    |> validate_inclusion(:visibility, @visibilities)
    |> validate_repository_fields()
    |> unique_constraint(:name)
  end

  def repository_attrs(%Ecto.Changeset{} = changeset) do
    owner = get_field(changeset, :github_repository_owner)
    name = get_field(changeset, :github_repository_name)
    visibility = get_field(changeset, :github_repository_visibility) || :public

    if present?(owner) and present?(name),
      do: %{owner: owner, name: name, visibility: visibility}
  end

  defp validate_repository_fields(changeset) do
    owner = get_field(changeset, :github_repository_owner)
    name = get_field(changeset, :github_repository_name)

    changeset
    |> validate_required_if_present(:github_repository_owner, owner, name)
    |> validate_required_if_present(:github_repository_name, name, owner)
    |> validate_length(:github_repository_owner, max: 39)
    |> validate_length(:github_repository_name, max: 100)
    |> validate_format(:github_repository_owner, ~r/^[a-z0-9][a-z0-9-]*[a-z0-9]$|^[a-z0-9]$/,
      message: "must be a valid GitHub owner"
    )
    |> validate_format(:github_repository_name, ~r/^[a-z0-9._-]+$/, message: "must be a valid GitHub repository name")
  end

  defp validate_required_if_present(changeset, field, value, paired_value) do
    if present?(paired_value) and not present?(value) do
      add_error(changeset, field, "can't be blank")
    else
      changeset
    end
  end

  defp present?(value), do: is_binary(value) and value != ""

  defp normalize_string(changeset, field, transform \\ &Function.identity/1) do
    update_change(changeset, field, fn
      value when is_binary(value) ->
        value
        |> String.trim()
        |> blank_to_nil()
        |> then(fn
          nil -> nil
          value -> transform.(value)
        end)

      value ->
        value
    end)
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value
end
