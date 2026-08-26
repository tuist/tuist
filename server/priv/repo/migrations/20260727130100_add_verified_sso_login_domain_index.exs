defmodule Tuist.Repo.Migrations.AddVerifiedSsoLoginDomainIndex do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    drop_if_exists index(
                     :organizations,
                     [:sso_login_domain],
                     name: :organizations_verified_sso_login_domain_index,
                     concurrently: true
                   )

    create unique_index(
             :organizations,
             [:sso_login_domain],
             where: "sso_login_domain_verified_at IS NOT NULL",
             name: :organizations_verified_sso_login_domain_index,
             concurrently: true
           )
  end

  def down do
    drop_if_exists index(
                     :organizations,
                     [:sso_login_domain],
                     name: :organizations_verified_sso_login_domain_index,
                     concurrently: true
                   )
  end
end
