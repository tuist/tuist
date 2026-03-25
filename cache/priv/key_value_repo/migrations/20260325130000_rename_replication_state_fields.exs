defmodule Cache.KeyValueRepo.Migrations.RenameReplicationStateFields do
  @moduledoc false
  use Ecto.Migration

  def change do
    rename table(:replication_state), :updated_at_value, to: :watermark_updated_at
    rename table(:replication_state), :key_value, to: :watermark_key
  end
end
