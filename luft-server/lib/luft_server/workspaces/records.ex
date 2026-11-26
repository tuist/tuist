defmodule LuftServer.Workspaces.Records do
  @moduledoc "Opt-in local workspace references, authorized independently of thread readership."

  alias LuftServer.Repo
  alias LuftServer.Sessions
  alias LuftServer.Threads
  alias LuftServer.Threads.Message
  alias LuftServer.Tuist.Scope
  alias LuftServer.Workspaces.Behaviors
  alias LuftServer.Workspaces.Definition
  alias LuftServer.Workspaces.Local

  def request(session, handle, thread_id, message_id, operation, body) do
    with {:ok, scope} <- Scope.load(session, handle),
         {:ok, _thread} <- Threads.get(scope, thread_id) do
      reference_request(scope, thread_id, message_id, operation, body)
    else
      {:error, :tuist_unavailable} -> {:error, :unavailable}
      _ -> {:error, :forbidden}
    end
  end

  defp reference_request(scope, thread_id, message_id, operation, body) do
    with {:ok, message_id} <- Ecto.UUID.cast(message_id),
         %Message{kind: "record", record_reference: reference} <-
           Repo.get_by(Message, id: message_id, thread_id: thread_id) do
      access(scope, reference, fn tx, catalog, ui, grants ->
        dispatch(
          tx,
          catalog,
          ui,
          grants,
          reference,
          operation,
          body,
          {scope.account_id, scope.user_id, thread_id, message_id}
        )
      end)
    else
      _ -> {:error, :not_found}
    end
  end

  def author(run, fun) do
    with %Message{kind: "human", author_id: author, author_session_id: session_id} <-
           Repo.get_by(Message, id: run.message_id, thread_id: run.thread_id),
         session when not is_nil(session) <- Sessions.get_by_id(session_id),
         true <- session.user_sub == to_string(author),
         thread when not is_nil(thread) <- Repo.get(Threads.Thread, run.thread_id),
         {:ok, scope} <- Scope.load(session, thread.account_handle),
         true <- scope.user_id == author,
         {:ok, _} <- Threads.get(scope, thread.id) do
      fun.(scope)
    else
      _ -> {:error, :not_found}
    end
  end

  def check(scope, %{"model" => model, "id" => id} = reference) when map_size(reference) == 2 do
    if Behaviors.configured?(scope) do
      case Behaviors.for_scope(scope, :get, %{"collection" => model, "id" => id}) do
        {:ok, _} -> {:ok, :ok}
        error -> error
      end
    else
      access(scope, reference, fn _tx, _catalog, _ui, _grants -> :ok end)
    end
  end

  def check(_, _), do: {:error, :forbidden}

  def discover(run, body), do: agent(run, :discover, body)
  def query(run, body), do: agent(run, :query, body)

  defp agent(run, operation, body) do
    Threads.with_attempt(run, fn _thread, fresh ->
      author(fresh, fn scope ->
        if Behaviors.configured?(scope),
          do: behavior_agent(scope, operation, body),
          else: runtime(scope, &agent_dispatch(&1, &2, &3, operation, body))
      end)
    end)
  end

  defp behavior_agent(scope, :discover, body) when map_size(body) == 0 do
    with {:ok, %{"collections" => collections}} <- Behaviors.for_scope(scope, :catalog) do
      {:ok,
       Enum.flat_map(collections, fn collection ->
         for operation <- ~w(list get) do
           %{
             "module" => collection["id"],
             "model" => collection["id"],
             "query" => collection["id"] <> "." <> operation,
             "operation" => operation
           }
         end
       end)}
    end
  end

  defp behavior_agent(
         scope,
         :query,
         %{"module" => collection, "query" => query, "input" => input} = body
       )
       when map_size(body) == 3 and is_binary(collection) and is_map(input) do
    # Session tools carry locators only. Protected field values never enter a shared journal.
    cond do
      query == collection <> ".list" ->
        with {:ok, %{"items" => items, "has_more" => more}} <-
               Behaviors.for_scope(scope, :query, Map.put(input, "collection", collection)) do
          {:ok,
           %{
             "references" => Enum.map(items, &%{"model" => collection, "id" => &1["id"]}),
             "has_more" => more
           }}
        end

      query == collection <> ".get" ->
        with {:ok, %{"record" => record}} <-
               Behaviors.for_scope(scope, :get, Map.put(input, "collection", collection)) do
          {:ok, %{"reference" => %{"model" => collection, "id" => record["id"]}}}
        end

      true ->
        {:error, :invalid_request}
    end
  end

  defp behavior_agent(_, _, _), do: {:error, :invalid_request}

  defp agent_dispatch(_tx, catalog, grants, :discover, body) when map_size(body) == 0 do
    catalog
    |> filtered(grants)
    |> Map.fetch!("ui_modules")
    |> Enum.flat_map(fn ui ->
      Enum.map(ui["capabilities"]["queries"], fn name ->
        Map.merge(catalog["queries"][name], %{"module" => ui["id"], "query" => name})
      end)
    end)
    |> Enum.take(100)
  end

  defp agent_dispatch(tx, catalog, grants, :query, %{"module" => module} = body) do
    case Enum.find(filtered(catalog, grants)["ui_modules"], &(&1["id"] == module)) do
      nil -> denied()
      ui -> dispatch(tx, catalog, ui, grants, nil, :query, body, nil)
    end
  end

  defp agent_dispatch(_, _, _, _, _), do: denied()

  defp access(scope, %{"model" => model, "id" => id} = reference, fun)
       when map_size(reference) == 2 do
    runtime(scope, fn tx, catalog, grants ->
      with true <- Definition.uuid?(id),
           [ui] <- Enum.filter(catalog["ui_modules"], &(&1["model"] == model)),
           {getter, _} <- getter(catalog, ui, grants),
           {:ok, %{"record" => _}} <-
             Local.query(tx, %{"query" => getter, "input" => %{"id" => id}}) do
        fun.(tx, catalog, ui, grants)
      else
        {:error, %{code: "NOT_FOUND"} = error} -> error
        _ -> denied()
      end
    end)
  end

  defp access(_, _, _), do: {:error, :forbidden}

  defp runtime(scope, fun) do
    case installation(scope) do
      {:ok, binding, grants} -> with_connection(binding, &authorized(&1, binding, grants, fun))
      _ -> {:error, :forbidden}
    end
  end

  defp authorized(connection, binding, grants, fun) do
    connection
    |> Local.authorized(fn tx, catalog ->
      with true <- is_map(catalog) and catalog["organization"] == binding.organization,
           :ok <- validate_catalog(catalog) do
        fun.(tx, catalog, grants)
      else
        _ -> denied()
      end
    end)
    |> flatten()
  end

  defp installation(scope) do
    with bindings when is_map(bindings) <- Application.get_env(:luft_server, :record_workspaces),
         binding when is_map(binding) <- bindings[{scope.organization_id, scope.account_id}],
         true <- is_integer(scope.organization_id),
         %{database: database, organization: organization, users: users} <- binding,
         true <- is_binary(database) and is_binary(organization) and is_map(users),
         %{queries: queries, actions: actions} = grants <- users[scope.user_id],
         true <- is_list(queries) and is_list(actions) do
      {:ok, binding, grants}
    else
      _ -> {:error, :not_found}
    end
  end

  defp validate_catalog(catalog) do
    catalog
    |> Map.drop(["apps"])
    |> Map.update!("ui_modules", &Enum.map(&1, fn ui -> Map.delete(ui, "source") end))
    |> Definition.validate!()

    Definition.ensure!(byte_size(catalog["title"]) <= 200, "Workspace title too long")
    Definition.ensure!(length(catalog["ui_modules"]) in 1..20, "Invalid module count")

    Enum.each(catalog["ui_modules"], fn ui ->
      source = ui["source"]

      Definition.ensure!(
        is_binary(source) and byte_size(source) in 1..262_144,
        "Invalid module source"
      )

      validate_module!(catalog, ui)
    end)

    :ok
  rescue
    _ -> {:error, :invalid_catalog}
  end

  defp validate_module!(catalog, ui) do
    Enum.each(~w(queries actions), fn kind ->
      Enum.each(ui["capabilities"][kind], fn name ->
        operation = catalog[kind][name]
        own_model = operation["model"] == ui["model"]

        linked_get =
          kind == "queries" and operation["operation"] == "get" and
            Enum.any?(catalog["models"][ui["model"]]["fields"], fn {_, field} ->
              field["type"] == "reference" and field["model"] == operation["model"]
            end)

        Definition.ensure!(own_model or linked_get, "Invalid module capability model")
      end)
    end)
  end

  defp getter(catalog, ui, grants) do
    Enum.find(catalog["queries"], fn {name, query} ->
      query == %{"model" => ui["model"], "operation" => "get"} and
        name in ui["capabilities"]["queries"] and name in grants.queries
    end)
  end

  defp dispatch(_tx, catalog, ui, grants, reference, :open, body, _context)
       when map_size(body) == 0 do
    %{workspace: filtered(catalog, grants), module: ui["id"], reference: reference}
  end

  defp dispatch(tx, catalog, ui, grants, _reference, operation, body, context)
       when operation in [:query, :action] and is_map(body) do
    kind = if operation == :query, do: "queries", else: "actions"
    key = Atom.to_string(operation)
    allowed = if operation == :query, do: grants.queries, else: grants.actions

    keys =
      if operation == :query, do: ~w(module query input), else: ~w(module action input request_id)

    with :ok <- closed(body, keys),
         true <- body["module"] == ui["id"],
         name when is_binary(name) <- body[key],
         true <- name in allowed and name in ui["capabilities"][kind],
         true <- linked_grants?(catalog, grants, kind, name, body["input"]) do
      request = Map.delete(body, "module")

      case operation do
        :query -> Local.query(tx, request)
        :action -> Local.action(tx, namespace(request, context))
      end
    else
      %{code: "INVALID_REQUEST"} = error -> error
      _ -> denied()
    end
  end

  defp dispatch(_, _, _, _, _, _, _, _), do: invalid()

  defp closed(body, keys) do
    if Enum.sort(Map.keys(body)) == Enum.sort(keys), do: :ok, else: invalid()
  end

  # Referencing another model in a write requires an independent get grant;
  # being allowed to read/write the source model does not imply that grant.
  defp linked_grants?(catalog, grants, "actions", name, %{"values" => values})
       when is_map(values) do
    model = catalog["actions"][name]["model"]

    Enum.all?(values, fn {field, value} ->
      case catalog["models"][model]["fields"][field] do
        %{"type" => "reference", "model" => target} when not is_nil(value) ->
          Enum.any?(catalog["queries"], fn {query, definition} ->
            query in grants.queries and definition == %{"model" => target, "operation" => "get"}
          end)

        _ ->
          true
      end
    end)
  end

  defp linked_grants?(_, _, _, _, _), do: true

  defp namespace(%{"request_id" => id} = request, context) do
    if Definition.uuid?(id) do
      <<uuid::binary-size(16), _::binary>> =
        :crypto.hash(:sha256, :erlang.term_to_binary({context, id}))

      Map.put(request, "request_id", Ecto.UUID.load!(uuid))
    else
      request
    end
  end

  defp namespace(request, _), do: request

  defp filtered(catalog, grants) do
    modules =
      catalog["ui_modules"]
      |> Enum.filter(&getter(catalog, &1, grants))
      |> Enum.map(fn ui ->
        Map.put(ui, "capabilities", %{
          "queries" => Enum.filter(ui["capabilities"]["queries"], &(&1 in grants.queries)),
          "actions" => Enum.filter(ui["capabilities"]["actions"], &(&1 in grants.actions))
        })
      end)

    catalog
    |> Map.put("ui_modules", modules)
    |> Map.put("queries", Map.take(catalog["queries"], grants.queries))
    |> Map.put("actions", Map.take(catalog["actions"], grants.actions))
  end

  defp with_connection(binding, fun) do
    connection = Local.connect!(binding.database)

    try do
      connection |> fun.() |> runtime_result()
    after
      GenServer.stop(connection)
    end
  rescue
    _ -> {:error, :unavailable}
  catch
    :exit, _ -> {:error, :unavailable}
  end

  defp runtime_result({:error, %{code: code}} = result)
       when code in ~w(FORBIDDEN NOT_FOUND REVISION_CONFLICT INVALID_REQUEST VALIDATION_FAILED),
       do: result

  defp runtime_result({:error, _}), do: {:error, :unavailable}
  defp runtime_result(result), do: result

  defp flatten({:ok, {:ok, result}}), do: {:ok, result}
  defp flatten({:ok, {:error, error}}), do: {:error, error}
  defp flatten(result), do: result
  defp denied, do: %{code: "FORBIDDEN", message: "Record unavailable"}
  defp invalid, do: %{code: "INVALID_REQUEST", message: "Record unavailable"}
end
