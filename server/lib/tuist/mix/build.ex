defmodule Tuist.Mix.Build do
  @moduledoc """
  Ecto schema for Mix (Elixir) compile builds stored in ClickHouse.

  Corresponds to a single `mix compile` invocation instrumented by the
  `tuist_ex` package. Test runs stay on `test_runs` with
  `build_system: "mix"`.
  """
  use Ecto.Schema
  use Tuist.Ingestion.Bufferable

  @derive {
    Flop.Schema,
    filterable: [
      :project_id,
      :account_id,
      :status,
      :is_ci,
      :git_branch,
      :elixir_version,
      :otp_version,
      :mix_env,
      :custom_tags,
      :inserted_at
    ],
    sortable: [:inserted_at, :duration_ms, :status],
    default_order: %{
      order_by: [:inserted_at],
      order_directions: [:desc]
    }
  }

  @primary_key false
  schema "mix_builds" do
    field :id, Ch, type: "UUID"
    field :project_id, Ch, type: "Int64"
    field :account_id, Ch, type: "Int64"
    belongs_to :ran_by_account, Tuist.Accounts.Account, foreign_key: :account_id, define_field: false
    field :duration_ms, Ch, type: "UInt64"
    field :status, Ch, type: "Enum8('success' = 0, 'failure' = 1)"
    field :is_ci, Ch, type: "Bool"
    field :elixir_version, Ch, type: "String"
    field :otp_version, Ch, type: "String"
    field :mix_env, Ch, type: "LowCardinality(String)"
    field :git_branch, Ch, type: "String"
    field :git_commit_sha, Ch, type: "String"
    field :git_ref, Ch, type: "String"
    field :git_remote_url_origin, Ch, type: "String"
    field :ci_provider, Ch, type: "LowCardinality(String)"
    field :ci_run_id, Ch, type: "String"
    field :ci_project_handle, Ch, type: "String"
    field :custom_tags, {:array, Ch}, type: "String", default: []
    field :custom_values, Ch, type: "Map(String, String)", default: %{}
    field :contract_version, Ch, type: "LowCardinality(String)"
    field :started_at, Ch, type: "Nullable(DateTime64(6))"
    field :diagnostics_error_count, Ch, type: "UInt32"
    field :diagnostics_warning_count, Ch, type: "UInt32"
    field :inserted_at, Ch, type: "DateTime"
  end
end
