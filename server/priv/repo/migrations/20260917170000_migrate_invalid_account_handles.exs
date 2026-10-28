defmodule Tuist.Repo.Migrations.MigrateInvalidAccountHandles do
  use Ecto.Migration

  # Accounts registered before handles were validated can hold handles no
  # account can be created or renamed with today, and those handles cannot name
  # the Kubernetes objects and hostnames of a Kura instance either.
  #
  # Each one becomes the closest valid handle: every run of other characters
  # turns into a hyphen, the ends lose theirs, and the result is cut to the
  # longest handle an account can hold. A handle another account holds, or a
  # reserved one, gets the lowest number that frees it, the way account creation
  # resolves a taken handle. Accounts that own projects are renamed first, so
  # when two legacy handles become the same one, the account in use keeps it
  # without a number.
  @valid_handle "^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?$"
  @max_length 32

  def up, do: migrate_invalid_handles!(repo())

  def down, do: :ok

  def migrate_invalid_handles!(repo) do
    reserved = MapSet.new(Application.get_env(:tuist, :blocked_handles, []), &String.downcase/1)

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    %{rows: rows} =
      repo.query!("""
      SELECT a.id, a.name
      FROM accounts a
      WHERE a.name !~ '#{@valid_handle}' OR char_length(a.name) > #{@max_length}
      ORDER BY EXISTS (SELECT 1 FROM projects p WHERE p.account_id = a.id) DESC, a.id
      """)

    Enum.each(rows, fn [id, name] ->
      handle = free_handle(repo, base_handle(id, name), reserved)

      # excellent_migrations:safety-assured-for-next-line raw_sql_executed
      repo.query!("UPDATE accounts SET name = $1, updated_at = NOW() WHERE id = $2", [handle, id])
    end)
  end

  defp base_handle(id, name) do
    case name |> String.replace(~r/[^A-Za-z0-9]+/, "-") |> String.trim("-") do
      "" -> "account-#{id}"
      handle -> handle
    end
  end

  defp free_handle(repo, base, reserved, number \\ nil) do
    suffix = if number, do: Integer.to_string(number), else: ""

    handle =
      base |> String.slice(0, @max_length - String.length(suffix)) |> String.trim_trailing("-")

    handle = handle <> suffix

    if taken?(repo, handle, reserved) do
      free_handle(repo, base, reserved, (number || 0) + 1)
    else
      handle
    end
  end

  # `accounts.name` is citext, so this matches regardless of casing, like the
  # unique index the rename has to satisfy.
  defp taken?(repo, handle, reserved) do
    MapSet.member?(reserved, String.downcase(handle)) or
      repo.query!("SELECT 1 FROM accounts WHERE name = $1", [handle]).num_rows > 0
  end
end
