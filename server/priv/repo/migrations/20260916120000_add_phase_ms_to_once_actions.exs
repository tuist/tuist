defmodule Tuist.Repo.Migrations.AddPhaseMsToOnceActions do
  use Ecto.Migration

  def change do
    alter table(:once_actions) do
      add :prepare_ms, :bigint, default: 0, null: false
      add :execute_ms, :bigint, default: 0, null: false
    end
  end
end
