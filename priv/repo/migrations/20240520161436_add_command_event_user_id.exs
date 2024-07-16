defmodule Tuist.Repo.Migrations.AddCommandEventUserId do
  use Ecto.Migration

  def change do
    alter table(:command_events) do
      add :user_id, :integer
    end
  end
end
