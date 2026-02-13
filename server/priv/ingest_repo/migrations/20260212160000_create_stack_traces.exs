defmodule Tuist.IngestRepo.Migrations.CreateStackTraces do
  use Ecto.Migration

  def up do
    create table(:stack_traces,
             primary_key: false,
             engine: "MergeTree",
             options: "PARTITION BY toYYYYMM(inserted_at) ORDER BY (id)"
           ) do
      add :id, :uuid, null: false
      add :file_name, :string, null: false
      add :app_name, :string, default: ""
      add :os_version, :string, default: ""
      add :exception_type, :string, default: ""
      add :signal, :string, default: ""
      add :exception_subtype, :string, default: ""
      add :raw_content, :string, null: false
      add :inserted_at, :"DateTime64(6)", default: fragment("now()")
    end
  end

  def down do
    drop table(:stack_traces)
  end
end
