defmodule TuistCloud.Projects.Project do
  @moduledoc """
  A module that represents the projects table.
  """
  use Ecto.Schema
  alias TuistCloud.Accounts.Account
  import Ecto.Changeset

  @type t :: %__MODULE__{
          token: String.t()
        }

  schema "projects" do
    field :token, :string
    field :name, :string
    belongs_to :account, Account

    # Rails names the field "created_at"
    timestamps(inserted_at: :created_at)
  end

  def create_changeset(project, attrs) do
    project
    |> cast(attrs, [:token, :account_id, :name])
    |> validate_required([:token, :account_id, :name])
  end
end
