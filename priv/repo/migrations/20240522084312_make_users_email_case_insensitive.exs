defmodule Tuist.Repo.Migrations.MakeUsersEmailCaseInsensitive do
  use Ecto.Migration

  def change do
    drop index(:users, [:email], name: "index_users_on_email")

    alter table(:users) do
      modify :email, :citext
    end

    create unique_index(:users, [:email], name: "index_users_on_email")
  end
end
