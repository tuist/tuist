alias Cache.Repo

%{rows: tables} =
  Repo.query!("""
  SELECT name FROM sqlite_master
  WHERE type='table'
    AND name NOT LIKE 'sqlite_%'
    AND name NOT LIKE 'oban_%'
    AND name != 'schema_migrations'
  """)

for [table_name] <- tables do
  %{rows: columns} = Repo.query!("PRAGMA table_info('#{table_name}')")

  {names, values} =
    columns
    |> Enum.map(fn [_cid, name, type, _notnull, _default, pk] ->
      type_upper = String.upcase(to_string(type))

      value =
        cond do
          pk == 1 and type_upper =~ "INT" -> nil
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
        System.halt(1)
    end
  end
end
