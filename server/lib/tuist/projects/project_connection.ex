defmodule Tuist.Projects.ProjectConnection do
  @moduledoc """
  A module that represents connections between Tuist projects and external repositories.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Accounts.Account
  alias Tuist.Projects.Project

  schema "project_connections" do
    field :provider, Ecto.Enum, values: [github: 0]
    field :external_id, :string
    field :repository_full_handle, :string

    belongs_to :project, Project
    belongs_to :created_by, Account, foreign_key: :created_by_id

    timestamps(type: :utc_datetime)
  end

  def changeset(project_connection \\ %__MODULE__{}, attrs) do
    project_connection
    |> cast(attrs, [:project_id, :provider, :external_id, :repository_full_handle, :created_by_id])
    |> validate_required([:project_id, :provider, :external_id, :repository_full_handle, :created_by_id])
    |> validate_format(:repository_full_handle, ~r/^[\w\-\.]+\/[\w\-\.]+$/)
    |> unique_constraint([:project_id, :provider, :external_id])
    |> foreign_key_constraint(:project_id)
    |> foreign_key_constraint(:created_by_id)
  end
end
