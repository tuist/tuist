defmodule Tuist.Repo.Migrations.AddSuspensionReleasedAtToKuraAccountRegionLifecycles do
  use Ecto.Migration

  def change do
    alter table(:kura_account_region_lifecycles) do
      add :suspension_released_at, :timestamptz
    end
  end
end
