defmodule Tuist.Repo.Migrations.EncryptWebhookEndpointUrls do
  use Ecto.Migration

  import Ecto.Query

  alias Tuist.Repo

  @disable_ddl_transaction true

  # The original `add_webhook_endpoints_table` migration first shipped
  # with `url :string`. Persisting the URL as authentication material
  # (`Tuist.Vault.Binary` on a `bytea` column) was a follow-up fix —
  # this migration converts any DB that already applied the old shape:
  #
  #   1. Re-encrypts the plaintext `url` of every existing row with
  #      `Tuist.Vault.encrypt/1`.
  #   2. Alters the column type to `bytea` so the schema's
  #      `Tuist.Vault.Binary` cast can decrypt it on read.
  #
  # On a fresh database the original migration has already been updated
  # to `add :url, :binary`, so this migration is a no-op (it skips when
  # the column is already `bytea`).
  def up do
    repo = Repo

    {:ok, %{rows: [[type]]}} =
      repo.query(
        """
        SELECT data_type
        FROM information_schema.columns
        WHERE table_name = 'webhook_endpoints'
          AND column_name = 'url'
        """,
        []
      )

    if type != "bytea" do
      # `mix ecto.migrate` boots a minimal app — the Vault GenServer
      # isn't in that supervision tree, so we start it ourselves before
      # touching `Tuist.Vault.encrypt/1`.
      {:ok, _} = Application.ensure_all_started(:cloak)
      Tuist.Vault.start_link([])

      # Flip the column to `bytea` first so we can write Cloak-encrypted
      # bytes back into it; the cast preserves the existing plaintext
      # URL as raw bytes, which we then re-encrypt row by row. `flush()`
      # forces the DDL to commit before the data migration so the UPDATE
      # below targets a `bytea` column.
      execute("ALTER TABLE webhook_endpoints ALTER COLUMN url TYPE bytea USING url::bytea")
      flush()

      repo.transaction(fn ->
        rows = repo.all(from(e in "webhook_endpoints", select: {e.id, e.url}))

        for {id, plaintext} <- rows, is_binary(plaintext) do
          {:ok, ciphertext} = Tuist.Vault.encrypt(plaintext)

          repo.update_all(
            from(e in "webhook_endpoints", where: e.id == ^id),
            set: [url: ciphertext]
          )
        end
      end)
    end
  end

  def down do
    # No-op: the original create-table migration owns the `:binary` shape
    # for fresh databases; rolling back to plaintext on already-converted
    # rows would expose secrets.
    :ok
  end
end
