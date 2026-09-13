defmodule Tuist.Repo.Migrations.CreateKuraPlacementProposals do
  use Ecto.Migration

  # Placement decisions carried through their rollout phases as one record,
  # the same shape claim sizing uses: the sweep writes proposals, an operator
  # applies or dismisses them from the ops account page, and automatic mode
  # lets the sweep apply them itself within a budget. Resolved rows are the
  # audit trail.
  #
  # A separate table from `kura_claim_proposals` rather than a kind column on
  # it. The budget that bounds unattended applies is counted from these rows,
  # and a region move costs a cold or peer-fed refill where a resize costs a
  # volume rebuild, so the two must not spend one budget: cheap resizes would
  # crowd out moves, or a move's budget would license five resizes.
  def change do
    create table(:kura_placement_proposals, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :kind, :string, null: false
      # Null on expansion, which adds a region without leaving one.
      add :from_region, :string
      # Null on retirement, which leaves a region without adding one.
      add :to_region, :string
      add :evidence, :map, null: false, default: %{}
      add :status, :string, null: false, default: "open"
      add :resolved_at, :timestamptz
      add :resolved_by, :string

      timestamps(type: :timestamptz)
    end

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:kura_placement_proposals, [:account_id])

    # One actionable placement decision per account at a time. The account is
    # the unit because the decisions interact: expanding into a region and
    # relocating the primary out of one are the same instance set being argued
    # about, and applying both from one sweep's evidence would act on a premise
    # the first apply already changed.
    # The table is new and empty, so building its unique index inline cannot block writes.
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:kura_placement_proposals, [:account_id],
             where: "status = 'open'",
             name: :kura_placement_proposals_one_open_per_account
           )

    # The relocation cap counts applied moves in a trailing window.
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:kura_placement_proposals, [:account_id, :kind, :resolved_at],
             where: "status = 'applied'",
             name: :kura_placement_proposals_applied_by_kind
           )
  end
end
