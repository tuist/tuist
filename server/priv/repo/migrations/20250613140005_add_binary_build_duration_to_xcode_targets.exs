defmodule Tuist.Repo.Migrations.AddBinaryBuildDurationToXcodeTargets do
  use Ecto.Migration

  def up do
    alter table(:xcode_targets) do
      add :binary_build_duration, :integer, null: true
    end
  end

  def down do
    secrets = Tuist.Environment.decrypt_secrets()

    if !Tuist.Environment.clickhouse_configured?(secrets) || Tuist.Environment.test?() do
      alter table(:xcode_targets) do
        remove :binary_build_duration, :integer
      end
    else
      # Table was dropped by later migration, nothing to rollback
      :ok
    end
  end
end
