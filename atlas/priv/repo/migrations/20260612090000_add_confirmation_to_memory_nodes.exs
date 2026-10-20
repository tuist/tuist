defmodule Atlas.Repo.Migrations.AddConfirmationToMemoryNodes do
  use Ecto.Migration

  def change do
    alter table(:memory_nodes) do
      add :confirmation, :string, null: false, default: "confirmed"
      add :proposal_slack_ts, :string
    end

    create index(:memory_nodes, [:confirmation, :forgotten])

    create unique_index(:memory_nodes, [:slack_channel_id, :proposal_slack_ts],
             where: "proposal_slack_ts IS NOT NULL",
             name: :memory_nodes_proposal_unique_index
           )
  end
end
