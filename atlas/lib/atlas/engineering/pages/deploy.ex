defmodule Atlas.Engineering.Pages.Deploy do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Atlas.Engineering.Pages.Page
  alias Atlas.Users.User

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @states [:pending, :live, :superseded, :failed]

  schema "page_deploys" do
    field :state, Ecto.Enum, values: @states, default: :pending
    field :file_count, :integer, default: 0
    field :total_bytes, :integer, default: 0
    field :manifest, {:array, :map}, default: []
    field :finalized_at, :utc_datetime

    belongs_to :page, Page
    belongs_to :uploaded_by_user, User

    timestamps(type: :utc_datetime)
  end

  def states, do: @states

  def changeset(deploy, attrs) do
    deploy
    |> cast(attrs, [
      :state,
      :file_count,
      :total_bytes,
      :manifest,
      :finalized_at,
      :page_id,
      :uploaded_by_user_id
    ])
    |> validate_required([:state, :page_id])
    |> validate_number(:file_count, greater_than_or_equal_to: 0)
    |> validate_number(:total_bytes, greater_than_or_equal_to: 0)
  end
end
