defmodule Atlas.Engineering.Projects.Project do
  @moduledoc """
  A project is the top-level grouping: a product, codebase, or service the
  instance tracks. Projects own their connected GitHub repositories and can
  be tagged with reusable domains.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Atlas.Engineering.Domains.Domain
  alias Atlas.Engineering.Domains.GitHubRepository
  alias Atlas.Engineering.Projects.ProjectDomain
  alias Atlas.Engineering.Projects.Webhook

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @visibilities [:public, :private]

  schema "projects" do
    field :name, :string
    field :description, :string
    field :visibility, Ecto.Enum, values: @visibilities, default: :public
    field :slack_alert_channel, :string

    many_to_many :domains, Domain,
      join_through: ProjectDomain,
      join_keys: [project_id: :id, domain_id: :id]

    has_many :github_repositories, GitHubRepository
    has_many :webhooks, Webhook

    timestamps(type: :utc_datetime)
  end

  def visibilities, do: @visibilities

  def changeset(project, attrs) do
    project
    |> cast(attrs, [:name, :description, :visibility, :slack_alert_channel])
    |> normalize_string(:name)
    |> normalize_string(:description)
    |> normalize_string(:slack_alert_channel)
    |> validate_required([:name, :visibility])
    |> validate_length(:name, max: 120)
    |> validate_length(:description, max: 500)
    |> validate_length(:slack_alert_channel, max: 120)
    |> validate_inclusion(:visibility, @visibilities)
    |> unique_constraint(:name)
  end

  defp normalize_string(changeset, field) do
    update_change(changeset, field, fn
      value when is_binary(value) ->
        value
        |> String.trim()
        |> blank_to_nil()

      value ->
        value
    end)
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value
end
