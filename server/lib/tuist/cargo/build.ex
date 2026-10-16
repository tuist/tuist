defmodule Tuist.Cargo.Build do
  @moduledoc "A Cargo invocation, observed by the Tuist CLI."
  use Ecto.Schema
  use Tuist.Ingestion.Bufferable

  @derive {Flop.Schema,
           filterable: [:project_id, :status, :is_ci, :git_branch, :command, :rust_version, :inserted_at],
           sortable: [:inserted_at, :duration_ms, :id],
           default_order: %{order_by: [:inserted_at], order_directions: [:desc]}}
  @primary_key false
  schema "cargo_builds" do
    field :id, Ch, type: "UUID"
    field :project_id, Ch, type: "Int64"
    field :account_id, Ch, type: "Int64"
    field :duration_ms, Ch, type: "UInt32"
    field :status, Ch, type: "Enum8('success' = 0, 'failure' = 1)"
    field :is_ci, Ch, type: "Bool"
    field :command, Ch, type: "String"
    field :rust_version, Ch, type: "String"
    field :contract_version, Ch, type: "String"
    field :cache_metrics, Ch, type: "String"
    field :git_branch, Ch, type: "String"
    field :git_commit_sha, Ch, type: "String"
    field :git_ref, Ch, type: "String"
    field :git_remote_url_origin, Ch, type: "String"
    field :ci_provider, Ch, type: "String"
    field :ci_run_id, Ch, type: "String"
    field :ci_project_handle, Ch, type: "String"
    field :ci_host, Ch, type: "String"
    field :started_at, Ch, type: "Nullable(DateTime64(6))"
    field :inserted_at, Ch, type: "DateTime"
    belongs_to :ran_by_account, Tuist.Accounts.Account, foreign_key: :account_id, define_field: false
  end
end
