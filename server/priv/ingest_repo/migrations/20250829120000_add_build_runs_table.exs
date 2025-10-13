defmodule Tuist.ClickHouseRepo.Migrations.AddBuildRunsTable do
  use Ecto.Migration

  def up do
    create table(:build_runs,
             primary_key: false,
             engine: "MergeTree",
             options: "ORDER BY (project_id, inserted_at)"
           ) do
      add :id, :uuid, null: false
      add :duration, :UInt64, null: false
      add :project_id, :UInt64, null: false
      add :account_id, :UInt64, null: false
      add :macos_version, :string, null: false
      add :xcode_version, :string, null: false
      add :is_ci, :boolean, null: false
      add :model_identifier, :string, null: false
      add :scheme, :string, null: false
      add :status, :"Enum8('success' = 0, 'failure' = 1)", null: false
      add :category, :"Enum8('clean' = 0, 'incremental' = 1, 'unknown' = 127)", null: false
      add :configuration, :string, null: false
      add :git_branch, :string, null: false
      add :git_commit_sha, :string, null: false
      add :git_ref, :string, null: false
      add :ci_run_id, :string, null: false
      add :ci_project_handle, :string, null: false
      add :ci_host, :string, null: false

      add :ci_provider,
          :"Enum8('github' = 0, 'gitlab' = 1, 'bitrise' = 2, 'circleci' = 3, 'buildkite' = 4, 'codemagic' = 5, 'unknown' = 127)",
          null: false

      add :inserted_at, :timestamp, default: fragment("now()")
    end

    copy_data_from_postgres()
  end

  def down do
    drop table(:build_runs)
  end

  defp copy_data_from_postgres do
    secrets = Tuist.Environment.decrypt_secrets()
    repo_config = Application.get_env(:tuist, Tuist.Repo, [])

    {username, password, host, port, database} =
      if database_url = Tuist.Environment.ipv4_database_url(secrets) do
        uri = URI.parse(database_url)

        {user, pass} =
          case String.split(uri.userinfo || "postgres:postgres", ":", parts: 2) do
            [username, password] -> {username, password}
            [username] -> {username, ""}
            _ -> {"postgres", "postgres"}
          end

        db_host = uri.host || "localhost"
        db_port = uri.port || 5432
        db_path = uri.path || "/tuist"

        db_name =
          case String.trim_leading(db_path, "/") do
            "" -> "tuist"
            name -> name
          end

        {user, pass, db_host, db_port, db_name}
      else
        db_name =
          case Keyword.get(repo_config, :database) do
            "tuist_test" <> _ = test_db ->
              test_db <> System.get_env("MIX_TEST_PARTITION", "")

            other ->
              other || "tuist_development"
          end

        {
          Keyword.get(repo_config, :username, "postgres"),
          Keyword.get(repo_config, :password, "postgres"),
          Keyword.get(repo_config, :hostname, "localhost"),
          Keyword.get(repo_config, :port, 5432),
          db_name
        }
      end

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    INSERT INTO build_runs (
      id,
      duration,
      project_id,
      account_id,
      macos_version,
      xcode_version,
      is_ci,
      model_identifier,
      scheme,
      status,
      category,
      configuration,
      git_branch,
      git_commit_sha,
      git_ref,
      ci_run_id,
      ci_project_handle,
      ci_host,
      ci_provider,
      inserted_at
    )
    SELECT
      id,
      toUInt64(duration),
      toUInt64(project_id),
      toUInt64(account_id),
      ifNull(macos_version, ''),
      ifNull(xcode_version, ''),
      is_ci,
      ifNull(model_identifier, ''),
      ifNull(scheme, ''),
      multiIf(status = 0, 'success', status = 1, 'failure', 'success'),
      multiIf(category = 0, 'clean', category = 1, 'incremental', 'unknown'),
      ifNull(configuration, ''),
      ifNull(git_branch, ''),
      ifNull(git_commit_sha, ''),
      ifNull(git_ref, ''),
      ifNull(ci_run_id, ''),
      ifNull(ci_project_handle, ''),
      ifNull(ci_host, ''),
      multiIf(
        ci_provider = 0,
        'github',
        ci_provider = 1,
        'gitlab',
        ci_provider = 2,
        'bitrise',
        ci_provider = 3,
        'circleci',
        ci_provider = 4,
        'buildkite',
        ci_provider = 5,
        'codemagic',
        'unknown'
      ),
      inserted_at
    FROM postgresql(
      '#{host}:#{port}',
      '#{database}',
      'build_runs',
      '#{username}',
      '#{password}',
      'public'
    )
    """
  end
end
