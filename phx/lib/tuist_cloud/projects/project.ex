defmodule TuistCloud.Projects.Project do
  @moduledoc """
  A module that represents the projects table.
  """
  use Ecto.Schema
  alias TuistCloud.Accounts.Account
  import Ecto.Changeset

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
    |> validate_change(:name, fn :name, name ->
      if String.contains?(name, ".") do
        [
          name:
            "Project name can't contain a dot. Please use a different name, such as #{String.replace(name, ".", "-")}."
        ]
      else
        []
      end
    end)
  end
end
