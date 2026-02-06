defmodule Tuist.Gradle.Build do
  @moduledoc """
  Ecto schema for Gradle builds stored in ClickHouse.
  """
  use Ecto.Schema

  @primary_key false
  schema "gradle_builds" do
    field :id, Ch, type: "UUID"
    field :project_id, Ch, type: "Int64"
    field :account_id, Ch, type: "Int64"
    belongs_to :built_by_account, Tuist.Accounts.Account, foreign_key: :account_id, define_field: false
    field :duration_ms, Ch, type: "UInt64"
    field :gradle_version, Ch, type: "Nullable(String)"
    field :java_version, Ch, type: "Nullable(String)"
    field :is_ci, Ch, type: "Bool"
    field :status, Ch, type: "Enum8('success' = 0, 'failure' = 1, 'cancelled' = 2)"
    field :git_branch, Ch, type: "Nullable(String)"
    field :git_commit_sha, Ch, type: "Nullable(String)"
    field :git_ref, Ch, type: "Nullable(String)"
    field :root_project_name, Ch, type: "Nullable(String)"
    field :tasks_local_hit_count, Ch, type: "UInt32"
    field :tasks_remote_hit_count, Ch, type: "UInt32"
    field :tasks_up_to_date_count, Ch, type: "UInt32"
    field :tasks_executed_count, Ch, type: "UInt32"
    field :tasks_failed_count, Ch, type: "UInt32"
    field :tasks_skipped_count, Ch, type: "UInt32"
    field :tasks_no_source_count, Ch, type: "UInt32"
    field :cacheable_tasks_count, Ch, type: "UInt32"
    field :inserted_at, Ch, type: "DateTime"

  end
end
