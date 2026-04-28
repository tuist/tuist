defmodule Tuist.Repo.Migrations.CreateOrchardTables do
  use Ecto.Migration

  # Embedded Orchard control plane: tables for the macOS Tart VM fleet
  # the Tuist server schedules (mac mini hosts running `orchard worker` +
  # the VMs running on them). API surface matches Cirrus Labs' upstream
  # Orchard JSON contract so their `orchard worker` daemon and our
  # vk-orchard provider both speak to it without modification.
  def change do
    create table(:orchard_service_accounts, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :name, :string, null: false
      # Hashed token (Bcrypt). The plaintext value only exists at creation
      # time and in the response body; we never persist it.
      add :token_hash, :string, null: false
      # Role list as JSONB — matches Cirrus's compute:read / compute:write /
      # compute:connect / admin:read / admin:write enum.
      add :roles, {:array, :string}, null: false, default: []

      timestamps(type: :timestamptz)
    end

    create unique_index(:orchard_service_accounts, [:name])

    create table(:orchard_workers, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :name, :string, null: false
      # `machine_id` is the Mac mini's stable hardware identifier — used
      # to detect "same name, different machine" conflicts.
      add :machine_id, :string
      # Server-only architecture: arm64 (Apple Silicon).
      add :arch, :string, null: false, default: "arm64"
      add :runtime, :string, null: false, default: "tart"
      # Cirrus's heartbeat: workers PUT their LastSeen. We reject jobs to
      # workers offline > heartbeat_timeout.
      add :last_seen_at, :timestamptz
      add :scheduling_paused, :boolean, null: false, default: false
      # Capacity reported by the worker (CPU cores, MiB memory, plus a
      # synthetic `tart-vms` resource Apple's licensing caps at 2/host).
      add :resources, :map, null: false, default: %{}
      add :labels, :map, null: false, default: %{}
      add :default_cpu, :integer, null: false, default: 4
      add :default_memory, :integer, null: false, default: 8192
      # Optimistic-concurrency version (Cirrus's WatchVM uses this).
      add :version, :bigint, null: false, default: 0

      timestamps(type: :timestamptz)
    end

    create unique_index(:orchard_workers, [:name])
    create index(:orchard_workers, [:last_seen_at])

    create table(:orchard_vms, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :name, :string, null: false
      # Unique per VM lifecycle — recreated on restart. Workers use this
      # to disambiguate "same name, fresh VM" after a crash.
      add :uid, :uuid, null: false
      add :image, :string, null: false
      add :image_pull_policy, :string, null: false, default: "if-not-present"
      # Spec
      add :cpu, :integer, null: false, default: 0
      add :memory, :integer, null: false, default: 0
      add :disk_size, :integer, null: false, default: 0
      add :headless, :boolean, null: false, default: true
      add :nested, :boolean, null: false, default: false
      add :startup_script, :text
      add :user_data, :text
      add :resources, :map, null: false, default: %{}
      add :labels, :map, null: false, default: %{}
      add :restart_policy, :string, null: false, default: "Never"
      # Status: pending | running | failed (Cirrus contract).
      add :status, :string, null: false, default: "pending"
      add :status_message, :text
      # Worker assignment (set by scheduler). Foreign-key by name to
      # match the upstream JSON contract — Cirrus encodes worker name,
      # not an ID, in the VM resource.
      add :worker_name, :string
      # Resolved values after scheduling (filled in by the scheduler
      # using either the VM's spec or the worker's defaults).
      add :assigned_cpu, :integer, null: false, default: 0
      add :assigned_memory, :integer, null: false, default: 0
      # Username/password the worker uses to SSH into the VM (filled by
      # base image; Cirrus convention is "admin"/"admin").
      add :username, :string, null: false, default: "admin"
      add :password, :string, null: false, default: "admin"
      # Optimistic-concurrency version.
      add :version, :bigint, null: false, default: 0
      # Lifecycle conditions (JSONB array of {type, state, ...}).
      add :conditions, {:array, :map}, null: false, default: []
      add :restart_count, :integer, null: false, default: 0
      add :restarted_at, :timestamptz

      timestamps(type: :timestamptz)
    end

    create unique_index(:orchard_vms, [:name])
    create index(:orchard_vms, [:worker_name])
    create index(:orchard_vms, [:status])

    # Per-VM event stream (logs, status transitions). Worker POSTs
    # batches; clients GET them with optional `since` cursor. Modeled
    # as a relational table here rather than ClickHouse because volume
    # is low (xcresult VMs emit ~hundreds of lines per parse, not
    # millions) and we need transactional consistency with vm.status
    # transitions.
    create table(:orchard_vm_events, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :vm_name, :string, null: false
      # Monotonic per-VM sequence — clients pass `?since=N` to get only
      # newer events.
      add :sequence, :bigint, null: false
      # Event kind: "log" | "condition" | "status".
      add :kind, :string, null: false
      add :payload, :map, null: false, default: %{}
      add :inserted_at, :timestamptz, null: false, default: fragment("NOW()")
    end

    create index(:orchard_vm_events, [:vm_name, :sequence])
  end
end
