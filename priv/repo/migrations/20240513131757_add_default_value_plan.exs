defmodule TuistCloud.Repo.Migrations.AddDefaultValuePlan do
  alias TuistCloud.Accounts.Account
  alias TuistCloud.Repo
  use Ecto.Migration
  import Ecto.Query

  def up do
    from(a in Account, where: is_nil(a.plan))
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
