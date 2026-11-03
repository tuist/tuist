# SQL targets only a connection-local temporary table inside a sandbox transaction.
# excellent_migrations:safety-assured-for-this-file operation_query operation_config
Code.require_file(
  Path.expand("../../../../priv/repo/migrations/20261028160000_add_vcs_comments_enabled_to_projects.exs", __DIR__)
)

defmodule Tuist.Repo.Migrations.AddVcsCommentsEnabledToProjectsTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Ecto.Migration.Runner
  alias Tuist.Repo
  alias Tuist.Repo.Migrations.AddVcsCommentsEnabledToProjects

  test "keeps existing projects enabled and defaults new projects to enabled" do
    Repo.query!("CREATE TEMP TABLE projects (id integer PRIMARY KEY)")
    Repo.query!("INSERT INTO pg_temp.projects VALUES (1), (2)")

    Runner.run(Repo, Repo.config(), 20_261_028_160_000, AddVcsCommentsEnabledToProjects, :forward, :change, :up,
      prefix: "pg_temp",
      log: false
    )

    Repo.query!("INSERT INTO pg_temp.projects (id) VALUES (3)")

    assert Repo.query!("SELECT id, vcs_comments_enabled FROM pg_temp.projects ORDER BY id").rows ==
             [[1, true], [2, true], [3, true]]

    Repo.query!("UPDATE pg_temp.projects SET vcs_comments_enabled = false WHERE id = 2")

    assert Repo.query!("SELECT id, vcs_comments_enabled FROM pg_temp.projects ORDER BY id").rows ==
             [[1, true], [2, false], [3, true]]

    assert Repo.query!("""
           SELECT attnotnull FROM pg_attribute
           WHERE attrelid = 'pg_temp.projects'::regclass AND attname = 'vcs_comments_enabled'
           """).rows == [[true]]
  end
end
