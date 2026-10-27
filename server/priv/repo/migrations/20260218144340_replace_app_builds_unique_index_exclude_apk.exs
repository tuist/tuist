defmodule Tuist.Repo.Migrations.ReplaceAppBuildsUniqueIndexExcludeApk do
  use Ecto.Migration

  def change do
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    drop_if_exists unique_index(:app_builds, [:binary_id, :build_version])

    # APK builds use a SHA256 hash of the file as binary_id, so re-uploading
    # the same unchanged APK is expected and should not be blocked.
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:app_builds, [:binary_id, :build_version],
             where: "type != 2",
             name: :app_builds_binary_id_build_version_non_apk_index
           )
  end
end
