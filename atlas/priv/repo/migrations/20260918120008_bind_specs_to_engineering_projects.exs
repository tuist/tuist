defmodule Atlas.Repo.Migrations.BindSpecsToEngineeringProjects do
  use Ecto.Migration

  def up do
    alter table(:specs) do
      add :engineering_project_id, references(:projects, type: :binary_id, on_delete: :restrict)
    end

    create index(:specs, [:engineering_project_id])

    flush()

    execute """
    UPDATE specs
    SET engineering_project_id = candidate_projects.project_id
    FROM (
      SELECT domains_specs.spec_id,
             (array_agg(DISTINCT projects_domains.project_id))[1] AS project_id
      FROM domains_specs
      INNER JOIN projects_domains ON projects_domains.domain_id = domains_specs.domain_id
      GROUP BY domains_specs.spec_id
      HAVING count(DISTINCT projects_domains.project_id) = 1
    ) AS candidate_projects
    WHERE candidate_projects.spec_id = specs.id
    """

    execute """
    UPDATE specs
    SET engineering_project_id = (SELECT id FROM projects LIMIT 1)
    WHERE engineering_project_id IS NULL
      AND (SELECT count(*) FROM projects) = 1
    """

    execute """
    INSERT INTO projects (id, name, description, visibility, inserted_at, updated_at)
    SELECT
      gen_random_uuid(),
      'Default project',
      NULL,
      'public',
      NOW() AT TIME ZONE 'UTC',
      NOW() AT TIME ZONE 'UTC'
    WHERE EXISTS (SELECT 1 FROM specs WHERE engineering_project_id IS NULL)
      AND NOT EXISTS (SELECT 1 FROM projects WHERE name = 'Default project')
    """

    execute """
    UPDATE specs
    SET engineering_project_id = (SELECT id FROM projects WHERE name = 'Default project')
    WHERE engineering_project_id IS NULL
    """

    execute "ALTER TABLE specs ALTER COLUMN engineering_project_id SET NOT NULL"
  end

  def down do
    drop index(:specs, [:engineering_project_id])

    alter table(:specs) do
      remove :engineering_project_id
    end
  end
end
