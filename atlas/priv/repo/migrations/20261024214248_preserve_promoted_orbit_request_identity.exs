defmodule Atlas.Repo.Migrations.PreservePromotedOrbitRequestIdentity do
  use Ecto.Migration

  def up do
    drop index(:orbit_threads, [:owner_id, :request_id],
           name: :orbit_threads_private_request_index
         )

    create unique_index(:orbit_threads, [:owner_id, :request_id],
             name: :orbit_threads_private_request_index,
             where: "request_id IS NOT NULL"
           )
  end

  def down do
    drop index(:orbit_threads, [:owner_id, :request_id],
           name: :orbit_threads_private_request_index
         )

    create unique_index(:orbit_threads, [:owner_id, :request_id],
             name: :orbit_threads_private_request_index,
             where: "kind = 'private' AND request_id IS NOT NULL"
           )
  end
end
