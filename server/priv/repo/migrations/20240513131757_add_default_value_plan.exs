defmodule Tuist.Repo.DataMigrations.Account.MigratingSchema do
  use Ecto.Schema

  schema "accounts" do
    field(:plan, Ecto.Enum, values: [none: 0, enterprise: 1, air: 2, pro: 3])
    field(:name, :string)
    field(:user_id, :integer)
    field(:organization_id, :integer)
    field(:cache_upload_event_count, :integer)
    field(:cache_download_event_count, :integer)
    field(:customer_id, :string)
    field(:enterprise_plan_seats, :integer)

    has_many(:projects, Project, on_delete: :delete_all)

    # credo:disable-for-next-line Credo.Checks.TimestampsType
    timestamps(inserted_at: :created_at)
  end
end

defmodule Tuist.Repo.Migrations.AddDefaultValuePlan do
  alias Tuist.Repo
  use Ecto.Migration
  import Ecto.Query

  def up do
    from(a in Tuist.Repo.DataMigrations.Account.MigratingSchema, where: is_nil(a.plan))
    |> Repo.update_all(set: [plan: :none])

    alter table(:accounts) do
      modify(:plan, :integer, null: false, default: 0)
    end
  end

  def down do
    alter table(:accounts) do
      modify(:plan, :integer, null: true)
    end
  end
end
