defmodule Tuist.Repo.Migrations.DropLegacyOauth2IdentityUserIndex do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  @index_name :idx_on_provider_id_in_provider_user_id_1ddc3fbf56

  def up do
    drop_if_exists unique_index(
                     :oauth2_identities,
                     [:provider, :id_in_provider, :user_id],
                     name: @index_name,
                     concurrently: true
                   )
  end

  def down do
    create_if_not_exists unique_index(
                           :oauth2_identities,
                           [:provider, :id_in_provider, :user_id],
                           name: @index_name,
                           concurrently: true
                         )
  end
end
