defmodule Tuist.Accounts.AccountTokenProject do
  @moduledoc """
  Join table linking account tokens to specific projects.

  This table is used when an account token's `all_projects` field is `false`.
  The token can only access projects that have an entry in this table.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Tuist.Accounts.AccountToken
  alias Tuist.Projects.Project

  @primary_key {:id, UUIDv7, autogenerate: true}
  schema "account_token_projects" do
    belongs_to :account_token, AccountToken, type: UUIDv7
    belongs_to :project, Project

    timestamps(type: :utc_datetime)
  end

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:account_token_id, :project_id])
    |> validate_required([:account_token_id, :project_id])
    |> unique_constraint([:account_token_id, :project_id])
    |> foreign_key_constraint(:account_token_id)
    |> foreign_key_constraint(:project_id)
  end
end
