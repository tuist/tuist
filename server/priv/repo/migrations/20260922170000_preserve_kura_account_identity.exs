defmodule Tuist.Repo.Migrations.PreserveKuraAccountIdentity do
  use Ecto.Migration

  def up do
    alter table(:accounts) do
      add :kura_tenant_id, :citext
    end

    create table(:account_handle_reservations, primary_key: false) do
      add :name, :citext, primary_key: true
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :inserted_at, :timestamptz, null: false, default: fragment("now()")
    end

    # This table is new and empty within this transaction.
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:account_handle_reservations, [:account_id])

    # Backfill, uniqueness and triggers must become visible atomically so old
    # server processes cannot insert an unbound identity between these steps.
    # Audit references and measure the locked transaction before rollout (see
    # kura/docs/account-renames.md). Unknown/conflicting identities abort it.
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    Enum.each(backfill_statements(), &execute/1)

    # Keep uniqueness in the same locked transaction as the identity backfill.
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:accounts, [:kura_tenant_id])

    # Populate the new reservation table before enabling writes through its trigger.
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    INSERT INTO account_handle_reservations (name, account_id)
    SELECT name, id FROM accounts UNION SELECT kura_tenant_id, id FROM accounts;
    """

    alter table(:accounts) do
      # Every row was backfilled above; the citext type is unchanged.
      # excellent_migrations:safety-assured-for-next-line not_null_added column_type_changed
      modify :kura_tenant_id, :citext, null: false
    end

    # Database functions enforce identity even for older server processes.
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    CREATE FUNCTION preserve_kura_account_identity() RETURNS trigger AS $$
    BEGIN
      IF TG_OP = 'INSERT' THEN
        NEW.kura_tenant_id := lower(NEW.name);
      ELSIF NEW.kura_tenant_id IS DISTINCT FROM OLD.kura_tenant_id THEN
        RAISE EXCEPTION 'Kura tenant identity is immutable';
      END IF;
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """

    # Install the identity guard before releasing the transaction's table lock.
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    CREATE TRIGGER preserve_kura_account_identity BEFORE INSERT OR UPDATE ON accounts
      FOR EACH ROW EXECUTE FUNCTION preserve_kura_account_identity();
    """

    # The conflict branch permits only the reservation's existing owner.
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    CREATE FUNCTION reserve_account_handle() RETURNS trigger AS $$
    DECLARE owner_id bigint;
    BEGIN
      INSERT INTO account_handle_reservations (name, account_id) VALUES (NEW.name, NEW.id)
      ON CONFLICT (name) DO UPDATE SET account_id = account_handle_reservations.account_id
        WHERE account_handle_reservations.account_id = EXCLUDED.account_id
      RETURNING account_id INTO owner_id;
      IF owner_id IS NULL THEN
        RAISE EXCEPTION 'Account handle is reserved'
          USING ERRCODE = '23505', CONSTRAINT = 'accounts_name_reserved';
      END IF;
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """

    # Install reservation enforcement atomically with the backfilled bindings.
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    CREATE TRIGGER reserve_account_handle AFTER INSERT OR UPDATE OF name ON accounts
      FOR EACH ROW EXECUTE FUNCTION reserve_account_handle();
    """
  end

  # Keep the historical naming vocabulary frozen and test the exact backfill SQL.
  def backfill_statements do
    [
      """
      CREATE TEMP TABLE kura_identity_backfill ON COMMIT DROP AS
      SELECT account_id,
             (regexp_match(provisioner_node_ref,
               '^kura-([a-z0-9][a-z0-9-]*)-(us-east-1|us-west-1|eu-west-1|eu-central-1|ca-east-1|ap-southeast-1|sa-west-1|eu-east-1|us-central-1|scw-fr-par|staging|local-controller)(-m)?$'))[1] AS tenant
      FROM kura_servers WHERE status <> 4;
      """,
      """
      DO $$ BEGIN
        IF EXISTS (SELECT 1 FROM kura_identity_backfill WHERE tenant IS NULL)
           OR EXISTS (SELECT 1 FROM kura_identity_backfill GROUP BY account_id HAVING count(DISTINCT tenant) > 1) THEN
          RAISE EXCEPTION 'Kura identity backfill requires an audit of unknown or conflicting provisioner references';
        END IF;
      END $$;
      """,
      """
      UPDATE accounts a SET kura_tenant_id = COALESCE(
        (SELECT min(tenant) FROM kura_identity_backfill b WHERE b.account_id = a.id), lower(a.name));
      """
    ]
  end

  def down do
    # Removing these bindings after a rename would reassign cache namespaces.
    raise "Kura identity migration is forward-only; retain bindings when rolling back application code"
  end
end
