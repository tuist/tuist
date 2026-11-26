defmodule LuftServer.Git.OpsRepository do
  @moduledoc false
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "organization_ops_repositories" do
    field :organization_id, :integer
    timestamps(type: :utc_datetime)
  end
end
