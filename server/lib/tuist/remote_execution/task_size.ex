defmodule Tuist.RemoteExecution.TaskSize do
  @moduledoc "What one remote action of a project used in its last runs (`Tuist.RemoteExecution.TaskSizes`)."
  use Ecto.Schema

  @primary_key false
  schema "remote_execution_task_sizes" do
    field :project_id, :integer, primary_key: true
    field :key, :string, primary_key: true
    field :target_label, :string
    field :mnemonic, :string
    field :anon_peak_bytes, :integer
    field :cores, :float
    field :p90_cores, :float
    field :wall_ms, :integer
    field :oom_floor_gb, :integer
    field :oom_floor_until, :utc_datetime
    field :runs, :integer, default: 1
    field :updated_at, :utc_datetime
  end
end
