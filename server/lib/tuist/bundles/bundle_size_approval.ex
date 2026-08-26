defmodule Tuist.Bundles.BundleSizeApproval do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, UUIDv7, autogenerate: false}
  @foreign_key_type UUIDv7
  schema "bundle_size_approvals" do
    field :bundle_id, UUIDv7
    field :approved_by_handle, :string

    belongs_to :project, Tuist.Projects.Project, type: :integer
    belongs_to :approved_by_user, Tuist.Accounts.User, type: :integer

    timestamps(type: :utc_datetime)
  end

  def changeset(approval, attrs) do
    approval
    |> cast(attrs, [:id, :bundle_id, :project_id, :approved_by_handle, :approved_by_user_id])
    |> validate_required([:bundle_id, :project_id, :approved_by_handle])
    |> foreign_key_constraint(:project_id)
    |> foreign_key_constraint(:approved_by_user_id)
    |> unique_constraint(:bundle_id)
  end
end
