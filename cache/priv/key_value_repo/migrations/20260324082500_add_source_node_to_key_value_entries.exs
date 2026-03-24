defmodule Cache.KeyValueRepo.Migrations.AddSourceNodeToKeyValueEntries do
  @moduledoc false
  use Ecto.Migration

  def change do
    alter table(:key_value_entries) do
      add(:source_node, :text)
    end
  end
end
