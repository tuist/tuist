defmodule Atlas.Repo.Migrations.DefaultTimeOffToBerlin do
  use Ecto.Migration

  def up do
    execute """
    INSERT INTO time_off_locations (id, name, country_code, subdivision_code, synced_years, inserted_at, updated_at)
    VALUES (gen_random_uuid(), 'Berlin', 'DE', 'DE-BE', '{}', NOW(), NOW())
    ON CONFLICT (name) DO NOTHING
    """

    execute """
    DO $$
    DECLARE berlin_id uuid;
    BEGIN
      SELECT id INTO STRICT berlin_id FROM time_off_locations WHERE name = 'Berlin';
      UPDATE users SET time_off_location_id = berlin_id WHERE time_off_location_id IS NULL;
      EXECUTE format('ALTER TABLE users ALTER COLUMN time_off_location_id SET DEFAULT %L::uuid', berlin_id);
    END $$
    """
  end

  def down do
    execute "ALTER TABLE users ALTER COLUMN time_off_location_id DROP DEFAULT"
  end
end
