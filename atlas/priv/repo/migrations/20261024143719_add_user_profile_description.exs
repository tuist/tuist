defmodule Atlas.Repo.Migrations.AddUserProfileDescription do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :description, :text, null: false, default: ""
    end

    create constraint(:users, :users_description_size,
             check: "char_length(description) <= 4000 AND octet_length(description) <= 16000"
           )
  end
end
