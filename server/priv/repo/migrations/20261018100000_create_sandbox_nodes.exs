defmodule Tuist.Repo.Migrations.CreateSandboxNodes do
  use Ecto.Migration

  # One row per sandbox node whose carve-out the server resizes in place.
  # `memory_limit_bytes` is the size the server last asked the daemon's Pod
  # for; placements budget against the smaller of it and the limit the node
  # reports, so a shrink stops new placements before the kubelet applies it.
  # `pod_name` tells a row about a replaced Pod, which starts at the floor
  # again. `grown_at` holds a grown carve-out for a while before it shrinks.
  def change do
    create table(:sandbox_nodes, primary_key: false) do
      add :name, :string, primary_key: true, null: false
      add :pod_name, :string, null: false
      add :memory_limit_bytes, :bigint, null: false
      add :grown_at, :timestamptz

      timestamps(type: :timestamptz)
    end
  end
end
