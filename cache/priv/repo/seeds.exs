alias Cache.Repo

%{rows: tables} =
  Repo.query!("""
  SELECT name FROM sqlite_master
  WHERE type='table'
    AND name NOT LIKE 'sqlite_%'
    AND name NOT LIKE 'oban_%'
    AND name != 'schema_migrations'
  """)

# Build a map of foreign keys per table: %{"col_name" => "referenced_table"}
fk_map = fn table_name ->
  %{rows: fks} = Repo.query!("PRAGMA foreign_key_list('#{table_name}')")

  fks
  |> Enum.map(fn [_id, _seq, ref_table, from, _to, _on_update, _on_delete, _match] ->
    {from, ref_table}
  end)
  |> Map.new()
end

for [table_name] <- tables do
  foreign_keys = fk_map.(table_name)
  %{rows: columns} = Repo.query!("PRAGMA table_info('#{table_name}')")

  {names, values} =
    columns
    |> Enum.map(fn [_cid, name, type, _notnull, _default, pk] ->
      type_upper = String.upcase(to_string(type))

      value =
        cond do
          pk == 1 and type_upper =~ "INT" -> nil
          Map.has_key?(foreign_keys, name) ->
            ref_table = Map.fetch!(foreign_keys, name)
            "(SELECT id FROM \"#{ref_table}\" LIMIT 1)"
          name == "id" -> "'#{Ecto.UUID.generate()}'"
          name =~ ~r/_at$/ -> "strftime('%Y-%m-%dT%H:%M:%f', 'now')"
          type_upper =~ "INT" -> "#{:rand.uniform(1_000_000)}"
          type_upper =~ "REAL" or type_upper =~ "FLOAT" -> "1.0"
          type_upper =~ "BLOB" -> "X'00'"
          true -> "'seed_#{name}_#{System.unique_integer([:positive])}'"
        end

      if value, do: {name, value}, else: nil
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.unzip()

  if names != [] do
    sql = "INSERT INTO \"#{table_name}\" (#{Enum.join(names, ", ")}) VALUES (#{Enum.join(values, ", ")})"

    case Repo.query(sql) do
      {:ok, _} -> IO.puts("  ✓ #{table_name}")
      {:error, error} ->
        IO.puts("  ✗ #{table_name}: #{Exception.message(error)}")
        IO.puts(sql)
        System.halt(1)
    end
  end
end
