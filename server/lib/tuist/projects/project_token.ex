defmodule Tuist.Projects.ProjectToken do
  @moduledoc """
  A module that represents a project token.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Projects.Project

  @primary_key {:id, UUIDv7, autogenerate: true}
  schema "project_tokens" do
    @doc """
    The project token's encrypted hash. The hash follows the following convention:
    "tuist_uuidv7-id_random-crypto-secure-hash"

    The unique identifier of the project is part of the hash, so we can look up the project token in the database based solely on the full token.
    """
    field(:encrypted_token_hash, :string)

    belongs_to :project, Project

    timestamps(type: :utc_datetime)
  end

  def create_changeset(token, attrs) do
    token
    |> cast(attrs, [:project_id, :encrypted_token_hash])
    |> validate_required([:project_id, :encrypted_token_hash])
    |> unique_constraint([:encrypted_token_hash])
  end
end
