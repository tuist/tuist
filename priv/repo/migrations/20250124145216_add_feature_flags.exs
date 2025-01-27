defmodule Tuist.Repo.Migrations.AddFeatureFlags do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    create table(:feature_flags, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :flag_name, :string, null: false
      add :gate_type, :string, null: false
      add :target, :string, null: false
      add :enabled, :boolean, null: false
    end

    create index(
             :feature_flags,
             [:flag_name, :gate_type, :target],
             unique: true,
             name: "fwf_flag_name_gate_target_idx",
             concurrently: true
           )
  end
end
