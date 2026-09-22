defmodule Atlas.Repo.Migrations.CreateAssetDataCenters do
  use Ecto.Migration

  def up do
    create table(:asset_data_centers, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :name, :string, null: false
      add :provider, :string
      add :city, :string
      add :country, :string
      add :notes, :text
      add :status, :string, null: false, default: "active"

      timestamps()
    end

    create unique_index(:asset_data_centers, [:name])
    create index(:asset_data_centers, [:status])

    create constraint(:asset_data_centers, :asset_data_centers_status_check,
             check: "status IN ('active','decommissioned')"
           )

    alter table(:assets) do
      add :data_center_id,
          references(:asset_data_centers, type: :binary_id, on_delete: :restrict)
    end

    create index(:assets, [:data_center_id])

    # Backfill: any asset already pinned to location = 'data_center' but without
    # a data_center_id gets pointed at a placeholder facility, so the invariant
    # below can be enforced without failing on legacy rows. The placeholder is
    # editable in the dashboard.
    execute("""
    INSERT INTO asset_data_centers (id, name, provider, notes, status, inserted_at, updated_at)
    SELECT
      gen_random_uuid(),
      'Unassigned facility',
      NULL,
      'Placeholder created during the data-center migration. Rename or reassign the linked assets to a real facility.',
      'active',
      NOW(),
      NOW()
    WHERE EXISTS (
      SELECT 1 FROM assets WHERE location = 'data_center' AND data_center_id IS NULL
    );
    """)

    execute("""
    UPDATE assets
    SET data_center_id = (
      SELECT id FROM asset_data_centers WHERE name = 'Unassigned facility' LIMIT 1
    )
    WHERE location = 'data_center' AND data_center_id IS NULL;
    """)

    create constraint(:assets, :assets_data_center_iff_location,
             check: "(location = 'data_center') = (data_center_id IS NOT NULL)"
           )
  end

  def down do
    drop constraint(:assets, :assets_data_center_iff_location)

    alter table(:assets) do
      remove :data_center_id
    end

    drop table(:asset_data_centers)
  end
end
