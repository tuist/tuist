defmodule Atlas.Demo.DatasetCheck do
  @moduledoc false
  use GenServer

  alias Atlas.Demo.Seeds
  alias Atlas.Repo
  alias Atlas.Users.User

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  @impl true
  def init(opts) do
    verify_permissions!()
    Seeds.verify!()
    if !Repo.exists?(User), do: raise("Seed the isolated Atlas demo database before starting the server")
    {:ok, opts}
  end

  def verify_permissions! do
    %{rows: [[database, read_only, writable?]]} =
      Repo.query!("""
      SELECT current_database(), current_setting('default_transaction_read_only'),
        (SELECT rolsuper OR rolcreaterole OR rolcreatedb OR rolbypassrls OR rolreplication
         FROM pg_roles WHERE rolname = current_user)
        OR has_schema_privilege(current_user, 'public', 'CREATE')
        OR EXISTS (
          SELECT 1 FROM pg_auth_members
          WHERE member = (SELECT oid FROM pg_roles WHERE rolname = current_user)
        )
        OR EXISTS (
          SELECT 1 FROM pg_database WHERE datname = current_database()
            AND datdba = (SELECT oid FROM pg_roles WHERE rolname = current_user)
        )
        OR EXISTS (
          SELECT 1 FROM pg_namespace
          WHERE nspowner = (SELECT oid FROM pg_roles WHERE rolname = current_user)
        )
        OR EXISTS (
          SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
          WHERE n.nspname = 'public' AND c.relkind IN ('r', 'p')
            AND (has_table_privilege(current_user, c.oid, 'INSERT, UPDATE, DELETE, TRUNCATE')
                 OR has_any_column_privilege(current_user, c.oid, 'INSERT, UPDATE'))
        )
      """)

    if !(database == "atlas_demo" and read_only == "on" and not writable?) do
      raise "Atlas demo serving requires the atlas_demo database and a SELECT-only role"
    end

    :ok
  end
end
