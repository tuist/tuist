defmodule Tuist.Repo.Migrations.CreateRunnerDispatchQueue do
  use Ecto.Migration

  # Burst queue. Each row is a pending workflow_job the webhook
  # handler accepted but a warm Pod hasn't claimed yet — either
  # because the fleet is saturated, or because the customer is at
  # `accounts.runner_max_concurrent` and the entry is waiting its
  # turn.
  #
  # A polling warm Pod's dispatch call claims the oldest row whose
  # account is currently below its cap (the count is taken from K8s
  # — Pods labeled with the account's name — at request time).
  # Claim is one SQL statement using `FOR UPDATE SKIP LOCKED` so
  # concurrent claims can't race onto the same row.
  #
  # Rows are deleted on claim. Per-account depth is checked at
  # enqueue (4 × max_concurrent) so one customer's sustained
  # over-rate can't flood the table.
  def change do
    create table(:runner_dispatch_queue) do
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :fleet_name, :string, null: false
      add :repo, :string, null: false

      timestamps(type: :timestamptz, updated_at: false)
    end

    # Oldest-eligible lookup per fleet.
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:runner_dispatch_queue, [:fleet_name, :inserted_at])

    # Per-account enqueue depth check + cascade on account delete.
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:runner_dispatch_queue, [:account_id])
  end
end
