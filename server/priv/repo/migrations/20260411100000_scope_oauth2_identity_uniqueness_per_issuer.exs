defmodule Tuist.Repo.Migrations.ScopeOauth2IdentityUniquenessPerIssuer do
  # credo:disable-for-this-file ExcellentMigrations.CredoCheck.MigrationsSafety
  use Ecto.Migration

  # OIDC `sub` is only unique per issuer (OIDC Core §2). Before this migration
  # the `(provider, id_in_provider)` uniqueness index treated `sub` as globally
  # unique across all custom OAuth2 (and Okta) issuers, which allowed a
  # cross-tenant account takeover: a malicious admin configuring a custom
  # OAuth2 IdP they control could return a `sub` that already belonged to a
  # victim user in a different organization, and the callback would log them
  # in as the victim.
  #
  # The correct key for per-issuer providers (`:okta` = 1, `:oauth2` = 4) is
  # `(provider, id_in_provider, provider_organization_id)`. Global providers
  # (`:github` = 0, `:google` = 2, `:apple` = 3) still use the old key.
  def up do
    # Abort early if any existing row would violate the new constraint. Safer
    # than silently dropping data or letting index creation fail later.
    execute """
    DO $$
    DECLARE
      orphan_count integer;
      duplicate_count integer;
    BEGIN
      SELECT count(*) INTO orphan_count
      FROM oauth2_identities
      WHERE provider IN (1, 4)
        AND (provider_organization_id IS NULL OR provider_organization_id = '');

      IF orphan_count > 0 THEN
        RAISE EXCEPTION
          'Cannot scope oauth2_identities uniqueness per issuer: % row(s) for provider okta/oauth2 have a NULL or empty provider_organization_id. Backfill or delete these rows before retrying.',
          orphan_count;
      END IF;

      SELECT count(*) INTO duplicate_count FROM (
        SELECT 1
        FROM oauth2_identities
        WHERE provider IN (1, 4)
        GROUP BY provider, id_in_provider, provider_organization_id
        HAVING count(*) > 1
      ) d;

      IF duplicate_count > 0 THEN
        RAISE EXCEPTION
          'Cannot scope oauth2_identities uniqueness per issuer: % duplicate group(s) under the new (provider, id_in_provider, provider_organization_id) key. Resolve duplicates before retrying.',
          duplicate_count;
      END IF;
    END $$;
    """

    drop unique_index(:oauth2_identities, [:provider, :id_in_provider],
           name: :index_oauth2_identities_on_provider_and_id_in_provider
         )

    # Global identity namespace (github, google, apple): `sub` is globally unique.
    create unique_index(
             :oauth2_identities,
             [:provider, :id_in_provider],
             name: :oauth2_identities_global_provider_unique_index,
             where: "provider IN (0, 2, 3)"
           )

    # Per-issuer namespace (okta, oauth2): `sub` is only unique within
    # `provider_organization_id`.
    create unique_index(
             :oauth2_identities,
             [:provider, :id_in_provider, :provider_organization_id],
             name: :oauth2_identities_per_issuer_unique_index,
             where: "provider IN (1, 4)"
           )
  end

  def down do
    drop unique_index(:oauth2_identities, [:provider, :id_in_provider, :provider_organization_id],
           name: :oauth2_identities_per_issuer_unique_index
         )

    drop unique_index(:oauth2_identities, [:provider, :id_in_provider],
           name: :oauth2_identities_global_provider_unique_index
         )

    create unique_index(:oauth2_identities, [:provider, :id_in_provider],
             name: :index_oauth2_identities_on_provider_and_id_in_provider
           )
  end
end
