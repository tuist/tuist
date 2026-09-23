defmodule Tuist.Repo.Migrations.ExpireKuraClientAliases do
  use Ecto.Migration

  def up do
    alter table(:account_handle_reservations) do
      add :client_url_expires_at, :timestamptz
    end

    # Only the newly added deadline is populated; ownership is unchanged. Keep
    # this atomic with trigger replacement so a concurrent rename gets a deadline.
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute backfill_statement()

    # Preserve the existing owner check while adding per-name URL deadlines.
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    CREATE OR REPLACE FUNCTION reserve_account_handle() RETURNS trigger AS $$
    DECLARE owner_id bigint;
    BEGIN
      INSERT INTO account_handle_reservations (name, account_id) VALUES (NEW.name, NEW.id)
      ON CONFLICT (name) DO UPDATE SET client_url_expires_at = NULL
        WHERE account_handle_reservations.account_id = EXCLUDED.account_id
      RETURNING account_id INTO owner_id;
      IF owner_id IS NULL THEN
        RAISE EXCEPTION 'Account handle is reserved'
          USING ERRCODE = '23505', CONSTRAINT = 'accounts_name_reserved';
      END IF;
      IF TG_OP = 'UPDATE' THEN
        IF OLD.name IS DISTINCT FROM NEW.name THEN
          UPDATE account_handle_reservations
          SET client_url_expires_at = now() + interval '90 days'
          WHERE name = OLD.name AND account_id = NEW.id;
        END IF;
      END IF;
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """
  end

  # Historical rename times are unknown. Give existing aliases the full window.
  def backfill_statement do
    """
    UPDATE account_handle_reservations r
    SET client_url_expires_at = now() + interval '90 days'
    FROM accounts a
    WHERE r.account_id = a.id AND r.name <> a.name;
    """
  end

  def down do
    raise "Client URL expiry migration is forward-only; retain deadlines and name reservations"
  end
end
