defmodule Atlas.Repo.Migrations.AddPocEndDateToAccounts do
  use Ecto.Migration

  def change do
    alter table(:accounts) do
      add :poc_end_date, :date
    end
  end
end
