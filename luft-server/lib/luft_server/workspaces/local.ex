defmodule LuftServer.Workspaces.Local do
  @moduledoc """
  Local-only PostgreSQL workspace rehearsal. One explicitly named disposable
  database holds one organization's installed definitions and business tables.
  This module is not mounted in the production router or application tree.
  """
  alias LuftServer.Workspaces.Definition, as: D

  def connect!(database, create? \\ false) do
    D.ensure!(
      is_binary(database) and Regex.match?(~r/\Aluft_workspace_[a-z0-9_]{1,40}\z/, database),
      "Use a disposable luft_workspace_* database"
    )

    config = Application.get_env(:luft_server, LuftServer.Repo, [])

    options = [
      hostname: System.get_env("LUFT_WORKSPACE_PGHOST", "localhost"),
      port: String.to_integer(System.get_env("LUFT_WORKSPACE_PGPORT", "5432")),
      username: System.get_env("LUFT_WORKSPACE_PGUSER", config[:username] || "postgres"),
      password: System.get_env("LUFT_WORKSPACE_PGPASSWORD", config[:password] || "postgres"),
      database: database,
      max_restarts: 0
    ]

    D.ensure!(
      options[:hostname] in ["localhost", "127.0.0.1", "::1"],
      "Local workspaces require loopback PostgreSQL"
    )

    if create? do
      {:ok, admin} = Postgrex.start_link(Keyword.put(options, :database, "postgres"))

      try do
        case Postgrex.query(admin, "CREATE DATABASE #{D.quote_id(database)}", []) do
          {:ok, _} -> :ok
          {:error, %{postgres: %{code: :duplicate_database}}} -> :ok
          {:error, error} -> raise error
        end
      after
        GenServer.stop(admin)
      end
    end

    {:ok, connection} = Postgrex.start_link(options)
    connection
  end

  def publish(connection, path) do
    definition = D.load(path)

    transaction(connection, fn tx ->
      sql(tx, "SELECT pg_advisory_xact_lock(179393101)")

      sql(
        tx,
        "CREATE TABLE IF NOT EXISTS workspace_catalog (singleton boolean PRIMARY KEY DEFAULT true CHECK (singleton), definition jsonb NOT NULL)"
      )

      sql(
        tx,
        "CREATE TABLE IF NOT EXISTS workspace_requests (id uuid PRIMARY KEY, payload jsonb NOT NULL, result jsonb NOT NULL)"
      )

      sql(
        tx,
        "CREATE TABLE IF NOT EXISTS workspace_audit (id bigserial PRIMARY KEY, request_id uuid UNIQUE NOT NULL, action text NOT NULL, record_id uuid NOT NULL, occurred_at timestamptz NOT NULL DEFAULT now())"
      )

      previous = catalog(tx)

      if previous,
        do:
          D.ensure!(
            previous["organization"] == definition["organization"],
            "Database already belongs to another organization"
          )

      old_models = if previous, do: previous["models"], else: %{}

      D.ensure!(
        Map.keys(old_models) -- Map.keys(definition["models"]) == [],
        "Model removal is not supported"
      )

      Enum.each(definition["models"], fn {id, model} ->
        install_model(tx, id, old_models[id], model)
      end)

      Enum.each(definition["models"], fn {id, model} ->
        old_fields = get_in(old_models, [id, "fields"]) || %{}

        model["fields"]
        |> Map.drop(Map.keys(old_fields))
        |> Enum.each(fn
          {key, %{"type" => "reference", "model" => target}} ->
            constraint = "fk_" <> String.slice(D.hash(id <> "." <> key), 0, 24)

            sql(
              tx,
              "ALTER TABLE #{table(id)} ADD CONSTRAINT #{D.quote_id(constraint)} FOREIGN KEY (#{D.quote_id(key)}) REFERENCES #{table(target)} (id) ON DELETE RESTRICT DEFERRABLE INITIALLY IMMEDIATE"
            )

          _ ->
            :ok
        end)
      end)

      sql(
        tx,
        "INSERT INTO workspace_catalog (definition) VALUES ($1) ON CONFLICT (singleton) DO UPDATE SET definition = EXCLUDED.definition",
        [definition]
      )

      %{
        organization: definition["organization"],
        models: map_size(definition["models"]),
        modules: length(definition["ui_modules"])
      }
    end)
  end

  def seed(connection, path) do
    authored = D.load(path)
    fixtures = D.fixtures(path)

    transaction(connection, fn tx ->
      sql(tx, "SELECT pg_advisory_xact_lock(179393101)")
      definition = catalog(tx)
      D.ensure!(definition == authored, "Publish this exact workspace before seeding")
      D.ensure!(is_map(fixtures), "Expected fixture records")
      sql(tx, "SET CONSTRAINTS ALL DEFERRED")

      count =
        Enum.reduce(fixtures, 0, fn {model, rows}, count ->
          D.ensure!(
            Map.has_key?(definition["models"], model) and is_list(rows),
            "Invalid fixture model"
          )

          existing = sql(tx, "SELECT count(*) FROM #{table(model)}").rows
          D.ensure!(existing == [[0]], "Refusing to seed a nonempty model")

          Enum.each(rows, &seed_record!(tx, model, definition["models"][model], &1))

          count + length(rows)
        end)

      # Check deferred references inside the transaction, not during COMMIT.
      sql(tx, "SET CONSTRAINTS ALL IMMEDIATE")
      count
    end)
  end

  defp seed_record!(tx, model_id, model, row) do
    {id, values} = Map.pop(row, "id")
    D.ensure!(valid_uuid?(id), "Fixture requires a UUID")

    case insert(tx, model_id, model, id, values, :seed) do
      {:ok, _} -> :ok
      {:error, error} -> raise ArgumentError, error.message
    end
  end

  def workspace(connection), do: transaction(connection, &catalog/1)

  # Integration authorization and execution share the publication lock. The local
  # preview API deliberately remains unchanged and supplies its own trust boundary.
  def authorized(connection, fun) do
    transaction(connection, fn tx ->
      sql(tx, "SELECT pg_advisory_xact_lock_shared(179393101)")

      installed = sql(tx, "SELECT to_regclass('workspace_catalog')").rows != [[nil]]

      case fun.(tx, if(installed, do: catalog(tx))) do
        {:error, error} -> Postgrex.rollback(tx, error)
        value -> value
      end
    end)
  end

  def query(connection, %{"query" => name, "input" => input} = request) when is_map(input) do
    transaction(connection, fn tx ->
      with true <- Map.keys(request) -- ~w(query input) == [],
           %{"operation" => operation, "model" => model} <- catalog(tx)["queries"][name] do
        run_query(tx, model, operation, input)
      else
        _ -> error("INVALID_REQUEST", "Unknown query or invalid input")
      end
    end)
  end

  def query(_connection, _), do: {:error, error("INVALID_REQUEST", "Invalid query")}

  defp run_query(tx, model, "list", input) when map_size(input) == 0,
    do: %{
      "items" =>
        records(sql(tx, "SELECT to_jsonb(t) FROM #{table(model)} t ORDER BY id LIMIT 100"))
    }

  defp run_query(tx, model, "get", %{"id" => id} = input) when map_size(input) == 1 do
    if valid_uuid?(id) do
      case records(
             sql(tx, "SELECT to_jsonb(t) FROM #{table(model)} t WHERE id = $1", [
               Ecto.UUID.dump!(id)
             ])
           ) do
        [record] -> %{"record" => record}
        [] -> error("NOT_FOUND", "Record not found")
      end
    else
      error("INVALID_REQUEST", "Invalid record ID")
    end
  end

  defp run_query(_, _, _, _), do: error("INVALID_REQUEST", "Invalid query input")

  def action(
        connection,
        %{"action" => name, "request_id" => request_id, "input" => input} = request
      )
      when is_map(input) do
    if valid_uuid?(request_id) and Map.keys(request) -- ~w(action request_id input) == [] do
      transaction(connection, fn tx ->
        # Shared definition lock prevents a publication changing a contract mid-action.
        sql(tx, "SELECT pg_advisory_xact_lock_shared(179393101)")

        sql(tx, "SELECT pg_advisory_xact_lock(hashtextextended(($1::text::uuid)::text, 0))", [
          request_id
        ])

        definition = catalog(tx)

        existing =
          sql(tx, "SELECT payload, result FROM workspace_requests WHERE id = $1::text::uuid", [
            request_id
          ])

        case existing.rows do
          [[^request, result]] ->
            result

          [[_, _]] ->
            error("REVISION_CONFLICT", "Request ID was already used with different input")

          [] ->
            execute(tx, definition, name, request_id, request)
        end
      end)
    else
      {:error, error("INVALID_REQUEST", "Action requires a UUID request ID and closed input")}
    end
  end

  def action(_connection, _), do: {:error, error("INVALID_REQUEST", "Invalid action")}

  defp execute(tx, definition, name, request_id, request) do
    case definition["actions"][name] do
      %{"model" => model, "operation" => operation} ->
        input = request["input"]

        result =
          case {operation, input} do
            {"create", %{"values" => values}} when map_size(input) == 1 ->
              insert(tx, model, definition["models"][model], Ecto.UUID.generate(), values)

            {"update", %{"id" => id, "expected_revision" => revision, "values" => values}}
            when map_size(input) == 3 ->
              update(tx, model, definition["models"][model], id, revision, values)

            _ ->
              {:error, error("INVALID_REQUEST", "Invalid action input")}
          end

        case result do
          {:ok, record} ->
            sql(
              tx,
              "INSERT INTO workspace_requests (id, payload, result) VALUES ($1::text::uuid, $2, $3)",
              [request_id, request, record]
            )

            sql(
              tx,
              "INSERT INTO workspace_audit (request_id, action, record_id) VALUES ($1::text::uuid, $2, $3::text::uuid)",
              [request_id, name, record["id"]]
            )

            record

          {:error, error} ->
            error
        end

      _ ->
        error("INVALID_REQUEST", "Unknown action")
    end
  end

  defp insert(tx, model_id, model, id, values, mode \\ :action) do
    with {:ok, values} <- validate_values(model, values, :create),
         :ok <- validate_references(tx, model, values, mode) do
      fields = values |> Map.keys() |> Enum.sort()
      columns = Enum.map_join(["id" | fields], ", ", &D.quote_id/1)
      placeholders = Enum.map_join(1..(length(fields) + 1), ", ", &"$#{&1}")

      parameters = [
        Ecto.UUID.dump!(id) | Enum.map(fields, &parameter(model["fields"][&1], values[&1]))
      ]

      record =
        tx
        |> sql(
          "INSERT INTO #{table(model_id)} AS t (#{columns}) VALUES (#{placeholders}) RETURNING to_jsonb(t)",
          parameters
        )
        |> records()
        |> hd()

      {:ok, record}
    end
  end

  defp update(tx, model_id, model, id, revision, values) do
    with true <- valid_uuid?(id) and is_integer(revision) and revision > 0,
         {:ok, values} <- validate_values(model, values, :update),
         :ok <- validate_references(tx, model, values, :action) do
      case records(
             sql(
               tx,
               "SELECT to_jsonb(t) FROM #{table(model_id)} t WHERE id = $1::text::uuid FOR UPDATE",
               [id]
             )
           ) do
        [] ->
          {:error, error("NOT_FOUND", "Record not found")}

        [%{"revision" => ^revision}] ->
          fields = values |> Map.keys() |> Enum.sort()

          assignments =
            fields
            |> Enum.with_index(1)
            |> Enum.map_join(", ", fn {key, index} -> "#{D.quote_id(key)} = $#{index}" end)

          parameters =
            Enum.map(fields, &parameter(model["fields"][&1], values[&1])) ++ [Ecto.UUID.dump!(id)]

          result =
            sql(
              tx,
              "UPDATE #{table(model_id)} AS t SET #{assignments}, revision = revision + 1 WHERE id = $#{length(parameters)} RETURNING to_jsonb(t)",
              parameters
            )

          {:ok, hd(records(result))}

        [_] ->
          {:error, error("REVISION_CONFLICT", "Record changed; reload before saving")}
      end
    else
      false -> {:error, error("INVALID_REQUEST", "Invalid record ID or revision")}
      error -> error
    end
  end

  defp validate_values(model, values, operation) when is_map(values) do
    fields = model["fields"]

    values =
      if operation == :create,
        do:
          Enum.reduce(fields, values, fn {key, field}, acc ->
            Map.put_new(acc, key, field["default"])
          end),
        else: values

    if map_size(values) > 0 and Map.keys(values) -- Map.keys(fields) == [] and
         Enum.all?(values, fn {key, value} -> D.valid_value?(fields[key], value) end) do
      {:ok, values}
    else
      {:error, error("VALIDATION_FAILED", "Provide valid values for the declared fields")}
    end
  end

  defp validate_values(_, _, _), do: {:error, error("VALIDATION_FAILED", "Expected field values")}

  defp parameter(%{"type" => "reference"}, value) when not is_nil(value),
    do: Ecto.UUID.dump!(value)

  defp parameter(_, value), do: value

  defp validate_references(_, _, _, :seed), do: :ok

  defp validate_references(tx, model, values, :action) do
    valid? =
      Enum.all?(values, fn {key, value} ->
        case model["fields"][key] do
          %{"type" => "reference", "model" => target} when not is_nil(value) ->
            sql(tx, "SELECT id FROM #{table(target)} WHERE id = $1 FOR KEY SHARE", [
              Ecto.UUID.dump!(value)
            ]).rows != []

          _ ->
            true
        end
      end)

    if valid?, do: :ok, else: {:error, error("VALIDATION_FAILED", "Reference target not found")}
  end

  defp install_model(tx, id, nil, model) do
    columns =
      model["fields"]
      |> Enum.sort()
      |> Enum.map_join(", ", fn {key, field} -> column(key, field) end)

    sql(
      tx,
      "CREATE TABLE #{table(id)} (id uuid PRIMARY KEY, revision bigint NOT NULL DEFAULT 1, #{columns})"
    )
  end

  defp install_model(tx, id, old, new) do
    if old != new do
      D.ensure!(new["version"] == old["version"] + 1, "A model change requires the next version")

      D.ensure!(
        Enum.all?(old["fields"], fn {key, field} -> new["fields"][key] == field end),
        "Only additive field migrations are supported in the local pilot"
      )

      added = Map.drop(new["fields"], Map.keys(old["fields"]))

      Enum.each(added, fn {key, field} ->
        D.ensure!(
          D.valid_value?(field, nil) or Map.has_key?(field, "default"),
          "New required fields need a valid default"
        )

        sql(tx, "ALTER TABLE #{table(id)} ADD COLUMN #{column(key, field)}")
      end)
    end
  end

  defp column(key, field) do
    name = D.quote_id(key)

    required =
      if field["required"] == true or field["nullable"] == false, do: " NOT NULL", else: ""

    default =
      if Map.has_key?(field, "default"), do: " DEFAULT #{literal(field["default"])}", else: ""

    values =
      if field["type"] == "enum",
        do: " AND #{name} IN (#{Enum.map_join(field["values"], ", ", &literal/1)})",
        else: ""

    if field["type"] == "reference" do
      "#{name} uuid#{required}#{default}"
    else
      nonempty = if field["required"] == true, do: " AND btrim(#{name}) <> ''", else: ""

      "#{name} text#{required}#{default} CHECK (octet_length(#{name}) <= 4000#{values}#{nonempty})"
    end
  end

  defp literal(nil), do: "NULL"
  defp literal(value), do: "'" <> String.replace(value, "'", "''") <> "'"
  defp table(id), do: D.quote_id(D.table(id))
  defp valid_uuid?(value), do: D.uuid?(value)

  defp sql(connection, statement, parameters \\ []),
    do: Postgrex.query!(connection, statement, parameters)

  defp catalog(tx) do
    case sql(tx, "SELECT definition FROM workspace_catalog WHERE singleton").rows do
      [[definition]] -> definition
      [] -> nil
    end
  end

  # PostgreSQL's JSON encoder preserves text while rendering every UUID canonically.
  defp records(%Postgrex.Result{rows: rows}), do: Enum.map(rows, fn [record] -> record end)

  defp transaction(connection, fun) do
    case Postgrex.transaction(connection, fn tx ->
           case fun.(tx) do
             %{code: _, message: _} = error -> Postgrex.rollback(tx, error)
             value -> value
           end
         end) do
      {:ok, value} -> {:ok, value}
      {:error, error} -> {:error, error}
    end
  end

  defp error(code, message), do: %{code: code, message: message}
end
