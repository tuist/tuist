defmodule Tuist.Repo.Migrations.AddDrainReasonToKuraAccountRegionLifecycles do
  use Ecto.Migration

  def change do
    alter table(:kura_account_region_lifecycles) do
      add :drain_reason, :string
    end
  end
end
