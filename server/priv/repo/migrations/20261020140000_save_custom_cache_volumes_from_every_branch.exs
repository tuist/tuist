defmodule Tuist.Repo.Migrations.SaveCustomCacheVolumesFromEveryBranch do
  @moduledoc false
  use Ecto.Migration

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute(statement())
  end

  def down, do: :ok

  # Profiles that kept the previous default, the default branch alone, now save
  # from every branch like new profiles. Customized profiles keep their policy.
  def statement do
    """
    UPDATE runner_profiles
       SET cache_writer_branches = ARRAY['*']::varchar[], updated_at = NOW()
     WHERE cache_writer_branches IS NULL AND cache_writer_default_branch
    """
  end
end
