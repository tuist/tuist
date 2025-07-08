defmodule Tuist.Repo.Migrations.CacheableTargetsAsArray do
  use Ecto.Migration

  def up do
    execute(
      "alter table command_events alter cacheable_targets type varchar(255)[] using string_to_array(cacheable_targets, ';'), alter cacheable_targets set default '{}'"
    )

    execute(
      "alter table command_events alter local_cache_target_hits type varchar(255)[] using string_to_array(local_cache_target_hits, ';'), alter local_cache_target_hits set default '{}'"
    )

    execute(
      "alter table command_events alter remote_cache_target_hits type varchar(255)[] using string_to_array(remote_cache_target_hits, ';'), alter remote_cache_target_hits set default '{}'"
    )
  end

  def down do
    execute(
      "alter table command_events alter cacheable_targets type varchar(255) using array_to_string(cacheable_targets, ';'), alter cacheable_targets drop default"
    )

    execute(
      "alter table command_events alter local_cache_target_hits type varchar(255) using array_to_string(local_cache_target_hits, ';'), alter local_cache_target_hits drop default"
    )

    execute(
      "alter table command_events alter remote_cache_target_hits type varchar(255) using array_to_string(remote_cache_target_hits, ';'), alter remote_cache_target_hits drop default"
    )
  end
end
