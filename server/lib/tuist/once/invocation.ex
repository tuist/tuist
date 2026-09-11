defmodule Tuist.Once.Invocation do
  @moduledoc """
  A completed `once exec` invocation reported by the Once CLI.

  Once wraps existing project automation (scripts, tests, codegen, package
  installs) in cacheable actions that pull from and push to a Bazel-compatible
  content-addressed store. Each invocation is a single action lookup: an input
  digest is derived, the action cache is probed, and either the cached result
  is restored (cache: hit) or the wrapped program is executed and its result
  recorded (cache: miss). This schema captures the summary the CLI emits after
  either path resolves, so the dashboard can rank invocations by wall time,
  see hit ratios, and follow the sequence of exec events for a project.
  """
  use Ecto.Schema

  import Ecto.Changeset

  @derive {
    Flop.Schema,
    filterable: [:project_id, :status, :cache, :is_ci, :command, :inserted_at],
    sortable: [:inserted_at, :started_at, :finished_at, :duration_ms, :status, :cache],
    default_order: %{order_by: [:finished_at], order_directions: [:desc]}
  }

  @primary_key {:id, UUIDv7, autogenerate: true}
  schema "once_invocations" do
    field :project_id, :integer
    field :invocation_id, :string
    field :command, :string, default: "exec"
    field :argv, {:array, :string}, default: []
    field :cwd, :string
    field :action_digest, :string
    field :cache, :string, default: "miss"
    field :status, :string
    field :exit_code, :integer
    field :duration_ms, :integer
    field :started_at, :utc_datetime
    field :finished_at, :utc_datetime
    field :git_branch, :string, default: ""
    field :git_commit_sha, :string, default: ""
    field :is_ci, :boolean, default: false
    field :remote_execution, :string
    field :os, :string, default: ""
    field :arch, :string, default: ""
    field :once_version, :string, default: ""
    field :workspace, :string, default: ""
    field :provider_name, :string, default: ""

    timestamps(type: :utc_datetime)
  end

  @required ~w(project_id invocation_id status exit_code duration_ms started_at finished_at)a
  @optional ~w(command argv cwd action_digest cache git_branch git_commit_sha is_ci remote_execution os arch once_version workspace provider_name)a

  @doc """
  Changeset for ingesting an invocation from the Once CLI payload.
  """
  def changeset(invocation \\ %__MODULE__{}, attrs) do
    invocation
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> validate_inclusion(:status, ["success", "failure"])
    |> validate_inclusion(:cache, ["hit", "miss", "bypass"])
    |> validate_length(:invocation_id, min: 1, max: 256)
    |> validate_length(:command, max: 64)
    |> validate_length(:action_digest, max: 256)
    |> validate_length(:git_branch, max: 1024)
    |> validate_length(:git_commit_sha, max: 128)
    |> validate_length(:os, max: 64)
    |> validate_length(:arch, max: 64)
    |> validate_length(:once_version, max: 64)
    |> validate_length(:workspace, max: 1024)
    |> validate_length(:provider_name, max: 128)
    |> validate_length(:remote_execution, max: 64)
    |> validate_length(:cwd, max: 1024)
    |> validate_number(:exit_code, greater_than_or_equal_to: -2_147_483_648)
    |> validate_number(:exit_code, less_than_or_equal_to: 2_147_483_647)
    |> validate_number(:duration_ms, greater_than_or_equal_to: 0)
  end
end
