defmodule Atlas.Repo.Migrations.AddHostedEnvironmentProviders do
  use Ecto.Migration

  def change do
    alter table(:personal_environments) do
      add :provider, :text, null: false, default: "native"
      add :provider_state, :text
      add :managed_thread_id, references(:orbit_threads, type: :uuid, on_delete: :nilify_all)
    end

    create unique_index(:personal_environments, [:managed_thread_id, :provider])
  end
end
