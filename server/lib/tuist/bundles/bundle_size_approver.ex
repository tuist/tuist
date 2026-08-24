defmodule Tuist.Bundles.BundleSizeApprover do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, UUIDv7, autogenerate: false}
  @foreign_key_type UUIDv7
  schema "bundle_size_approvers" do
    field :github_handle, :string

    # GitHub's `id` for the account, read from `GET /users/{username}` when the
    # approver is added and compared against the webhook's `sender.id`.
    field :github_id, :string

    belongs_to :project, Tuist.Projects.Project, type: :integer

    timestamps(type: :utc_datetime)
  end

  def changeset(approver, attrs) do
    approver
    |> cast(attrs, [:id, :github_handle, :github_id, :project_id])
    |> update_change(:github_handle, &(&1 |> String.trim() |> String.trim_leading("@") |> String.downcase()))
    |> validate_required([:github_handle, :github_id, :project_id])
    |> validate_format(:github_handle, ~r/^[a-z\d](?:[a-z\d]|-(?=[a-z\d])){0,38}$/,
      message: "must be a valid GitHub username"
    )
    |> foreign_key_constraint(:project_id)
    |> unique_constraint(:github_handle, name: "bundle_size_approvers_project_id_github_handle_index")
    |> unique_constraint(:github_handle, name: "bundle_size_approvers_project_id_github_id_index")
  end
end
