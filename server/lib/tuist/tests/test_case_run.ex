defmodule Tuist.Tests.TestCaseRun do
  @moduledoc """
  A test case run represents execution of a single test case.
  This is a ClickHouse entity that stores test case run data.
  """
  use Ecto.Schema
  use Tuist.Ingestion.Bufferable

  import Ecto.Changeset

  alias Tuist.Accounts.Account

  @derive {
    Flop.Schema,
    filterable: [
      :test_run_id,
      :test_module_run_id,
      :test_suite_run_id,
      :test_case_id,
      :project_id,
      :name,
      :status,
      :is_flaky,
      :is_new,
      :duration,
      :is_ci,
      :account_id,
      :verified_actor,
      :claimed_actor_id,
      :scheme,
      :git_branch,
      :shard_id,
      :shard_index
    ],
    sortable: [:inserted_at, :duration, :name, :ran_at, :id],
    adapter_opts: [
      custom_fields: [
        verified_actor: [
          filter: {Tuist.ReportActor, :verified_account_filter, []},
          ecto_type: :integer,
          operators: [:==, :!=]
        ]
      ]
    ]
  }

  @primary_key {:id, Ecto.UUID, autogenerate: false}
  schema "test_case_runs" do
    field :name, Ch, type: "String"
    field :test_run_id, Ecto.UUID
    field :test_module_run_id, Ecto.UUID
    field :test_suite_run_id, Ecto.UUID
    field :test_case_id, Ch, type: "Nullable(UUID)"
    field :project_id, Ch, type: "Int64"
    field :is_ci, :boolean, default: false
    field :scheme, Ch, type: "String"
    field :account_id, Ch, type: "Nullable(Int64)"
    field :actor_account_id, Ch, type: "Int64", default: 0
    field :claimed_actor_id, Ch, type: "String", default: ""
    field :submission_auth, Ch, type: "LowCardinality(String)", default: ""
    field :ran_at, Ch, type: "DateTime64(6)"
    field :git_branch, Ch, type: "String"
    field :is_default_branch, :boolean, default: false
    field :git_commit_sha, Ch, type: "String"
    field :status, Ch, type: "Enum8('success' = 0, 'failure' = 1, 'skipped' = 2)"
    field :is_flaky, :boolean, default: false
    field :is_new, :boolean, default: false
    field :is_quarantined, :boolean, default: false
    field :coverage_evidence, Ch, type: "Enum8('none' = 0, 'own' = 1, 'overlapped' = 2)", default: "none"
    field :duration, Ch, type: "Int32"
    field :inserted_at, Ch, type: "DateTime64(6)"
    field :module_name, Ch, type: "String"
    field :suite_name, Ch, type: "String"
    field :shard_id, Ch, type: "Nullable(UUID)"
    field :shard_index, Ch, type: "Nullable(Int32)"

    belongs_to :ran_by_account, Account, foreign_key: :account_id, define_field: false
    belongs_to :actor_account, Account, foreign_key: :actor_account_id, define_field: false

    has_one :crash_report, Tuist.Tests.CrashReport, foreign_key: :test_case_run_id
    has_many :attachments, Tuist.Tests.TestCaseRunAttachment, foreign_key: :test_case_run_id
    has_many :arguments, Tuist.Tests.TestCaseRunArgument, foreign_key: :test_case_run_id
    has_many :failures, Tuist.Tests.TestCaseFailure, foreign_key: :test_case_run_id
    has_many :repetitions, Tuist.Tests.TestCaseRunRepetition, foreign_key: :test_case_run_id
  end

  def create_changeset(test_case_run, attrs) do
    test_case_run
    |> cast(attrs, [
      :id,
      :name,
      :test_run_id,
      :test_module_run_id,
      :test_suite_run_id,
      :test_case_id,
      :project_id,
      :is_ci,
      :scheme,
      :account_id,
      :actor_account_id,
      :claimed_actor_id,
      :submission_auth,
      :ran_at,
      :git_branch,
      :is_default_branch,
      :git_commit_sha,
      :status,
      :is_flaky,
      :is_new,
      :is_quarantined,
      :coverage_evidence,
      :duration,
      :inserted_at,
      :module_name,
      :suite_name,
      :shard_id,
      :shard_index
    ])
    |> validate_required([
      :id,
      :name,
      :test_run_id,
      :test_module_run_id,
      :status,
      :duration,
      :module_name,
      :suite_name
    ])
    |> validate_inclusion(:status, ["success", "failure", "skipped"])
  end
end
