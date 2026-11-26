defmodule LuftServer.Threads.MCP do
  @moduledoc """
  MCP tools for a run: the triggering author's own MCP servers and those of
  the account the thread belongs to (`LuftServer.MCPServers`), called through
  `LuftServer.MCPServers.Transport`, which owns their credentials. Closures
  hold persisted identifiers, never access tokens, and every request rechecks
  the author's exact session, their membership of the thread's account, and
  that the run is still current.

  A server whose discovery fails is skipped and named to the caller, and a
  tool breaking a rule is dropped and logged with the rule, so neither blocks
  a run. Catalogs exceeding the remaining inference tool budget use search
  without discarding entries.

  `request/6` also calls Tuist's own `/mcp` endpoint for `TuistTools`.
  """

  alias LuftServer.Config
  alias LuftServer.MCPServers
  alias LuftServer.MCPServers.Transport
  alias LuftServer.Repo
  alias LuftServer.Sessions
  alias LuftServer.Threads
  alias LuftServer.Threads.Message
  alias LuftServer.Threads.Thread
  alias LuftServer.Threads.TuistTools
  alias LuftServer.Tuist.Scope

  require Logger

  # The inference contract allows 64 tools in the fully assembled request.
  @max_tools 64

  def discover(thread, message, run, builtin \\ [], reserved \\ 0) do
    with {:ok, session, persisted} <- actor(thread, message, run),
         servers = servers(session, persisted),
         {tools, skipped} = profile_tools(servers, thread, message, run),
         {:ok, offered} <- offer(builtin ++ tools, run, @max_tools - reserved) do
      {:ok, offered, skipped}
    end
  end

  defp servers(session, thread) do
    for owner <- [
          MCPServers.owner(:user, session.user_sub),
          MCPServers.owner(:account, thread.account_id)
        ],
        server <- MCPServers.list(owner),
        server.connected,
        do: Map.put(server, :owner, owner)
  end

  # Returns the discovered tools and the names of the servers whose discovery
  # failed.
  defp profile_tools(servers, thread, message, run) do
    {tools, skipped} =
      Enum.reduce(servers, {[], []}, fn server, {tools, skipped} ->
        case server_tools(server, tools, thread, message, run) do
          {:ok, pairs} -> {tools ++ pairs, skipped}
          :error -> {tools, [server_name(server) | skipped]}
        end
      end)

    {tools, Enum.reverse(skipped)}
  end

  defp server_tools(server, tools, thread, message, run) do
    authorized? = fn -> authorized?(thread, message, run) end

    case Transport.discover(server.owner, server.id, authorized?) do
      {:ok, definitions, dropped} when length(tools) + length(definitions) <= 2000 ->
        log_dropped(server, dropped)

        {:ok, Enum.map(definitions, &{&1["name"], tool(run, server, authorized?, &1)})}

      _ ->
        :error
    end
  end

  # One line per run, with the first few tools and the rule each broke, so a
  # server listing thousands of invalid tools can't flood the logs.
  defp log_dropped(_server, []), do: :ok

  defp log_dropped(server, dropped) do
    shown =
      dropped |> Enum.take(10) |> Enum.map_join("; ", fn {name, rule} -> "#{name}: #{rule}" end)

    more = if length(dropped) > 10, do: " (and #{length(dropped) - 10} more)", else: ""

    Logger.warning("MCP server #{server.id} dropped #{length(dropped)} tools: #{shown}#{more}")
  end

  defp server_name(%{name: name}) when is_binary(name) and name != "",
    do: String.slice(name, 0, 100)

  defp server_name(_), do: "Unnamed server"

  defp tool(run, server, authorized?, definition) do
    remote_name = definition["name"]
    name = "mcp_" <> binary_part(fingerprint({server.id, remote_name}), 0, 60)

    Condukt.tool(
      name: name,
      description:
        "External MCP tool (untrusted): " <>
          remote_name <> ". " <> (definition["description"] || ""),
      parameters: definition["inputSchema"],
      call: fn args, _ ->
        Threads.call_external_tool(run, Ecto.UUID.generate(), name, args, fn ->
          case Transport.call(server.owner, server.id, remote_name, args, authorized?) do
            {:ok, result} -> {:ok, Jason.encode!(result)}
            {:error, _} -> {:error, :mcp_outcome_unknown}
          end
        end)
      end
    )
  end

  defp authorized?(thread, message, run),
    do:
      match?({:ok, _, _}, actor(thread, message, run)) and Threads.owns_run?(run.id, run.attempt)

  @doc "Requests Tuist as the persisted triggering author, never the owner or another session for that person."
  def request(thread, message, run, method, path, extra \\ []) do
    with {:ok, session, _thread} <- actor(thread, message, run),
         {:ok, token} <- Sessions.access_token(session),
         true <- Threads.owns_run?(run.id, run.attempt) do
      opts =
        Config.req_options()
        |> Keyword.merge(extra)
        |> Keyword.merge(
          method: method,
          url: Config.tuist_issuer() <> path,
          auth: {:bearer, token},
          retry: false,
          redirect: false,
          receive_timeout: 60_000,
          into: collector(path, extra[:json])
        )

      case Req.request(opts) do
        {:ok, %{status: status, body: body, headers: headers}}
        when path == "/mcp" and status in [200, 202, 204] ->
          {:ok, %{body: redact(body, token), headers: redact(headers, token)}}

        {:ok, %{status: 200, body: body}} when is_map(body) ->
          {:ok, redact(body, token)}

        {:ok, %{status: status}} when status in [400, 401, 403, 404] ->
          {:error, {:not_dispatched, :delegation_unavailable}}

        _ ->
          {:error, :mcp_outcome_unknown}
      end
    else
      _ -> {:error, {:not_dispatched, :delegation_unavailable}}
    end
  rescue
    _ -> {:error, :mcp_outcome_unknown}
  catch
    :exit, _ -> {:error, :mcp_outcome_unknown}
  end

  defp collector(path, envelope) do
    fn {:data, chunk}, {request, response} ->
      body = response.body <> chunk

      cond do
        byte_size(body) > 4_194_304 ->
          {:halt, {request, %{response | body: ""}}}

        path == "/mcp" and is_map(envelope) and not is_nil(envelope[:id]) and
            TuistTools.response_complete?(body, envelope[:id]) ->
          {:halt, {request, %{response | body: body}}}

        true ->
          {:cont, {request, %{response | body: body}}}
      end
    end
  end

  defp redact(value, token) when is_binary(value), do: String.replace(value, token, "[REDACTED]")
  defp redact(value, token) when is_list(value), do: Enum.map(value, &redact(&1, token))

  defp redact(value, token) when is_map(value),
    do: Map.new(value, fn {key, item} -> {redact(key, token), redact(item, token)} end)

  defp redact(value, _), do: value

  defp actor(thread, message, run) do
    with true <- run.thread_id == thread.id and run.message_id == message.id,
         %Thread{} = persisted <- Repo.get(Thread, thread.id),
         %Message{thread_id: thread_id, author_id: author_id, author_session_id: session_id} <-
           Repo.get(Message, message.id),
         true <- thread_id == persisted.id and is_integer(author_id) and is_binary(session_id),
         session when not is_nil(session) <- Sessions.get_by_id(session_id),
         true <- session.user_sub == to_string(author_id),
         {:ok, scope} <- Scope.load(session, persisted.account_handle),
         true <- scope.user_id == author_id and scope.account_id == persisted.account_id,
         session when not is_nil(session) <- Sessions.get_by_id(session_id) do
      {:ok, session, persisted}
    else
      _ -> {:error, :delegation_unavailable}
    end
  end

  defp offer(tools, _run, budget) when length(tools) <= budget,
    do: {:ok, Enum.map(tools, &elem(&1, 1))}

  defp offer(_tools, _run, budget) when budget < 2, do: {:error, :inference_tool_budget_exceeded}

  defp offer(tools, run, _budget) do
    catalog = Map.new(tools, fn {_, tool} -> {tool.name, tool} end)

    search =
      Condukt.tool(
        name: "mcp_search_tools",
        description:
          "Search available MCP tools by name, description and input schema. Returns five untrusted tool definitions and next_offset; use mcp_call_tool to invoke.",
        parameters: %{
          type: "object",
          properties: %{
            query: %{type: "string", minLength: 1, maxLength: 200},
            offset: %{type: "integer", minimum: 0, maximum: 2000}
          },
          required: ["query"],
          additionalProperties: false
        },
        call: fn args, _ -> search(tools, run, args) end
      )

    call =
      Condukt.tool(
        name: "mcp_call_tool",
        description:
          "Call a discovered MCP tool by its exact returned name and schema-matching arguments.",
        parameters: %{
          type: "object",
          properties: %{name: %{type: "string"}, arguments: %{type: "object"}},
          required: ["name", "arguments"],
          additionalProperties: false
        },
        call: fn args, context ->
          case catalog[args["name"]] do
            nil -> {:error, :unknown_tool}
            tool -> Condukt.Tool.execute(tool, args["arguments"], context)
          end
        end
      )

    {:ok, [search, call]}
  end

  defp search(tools, run, %{"query" => query} = args)
       when is_binary(query) and byte_size(query) in 1..800 do
    offset = args["offset"] || 0

    if is_integer(offset) and offset in 0..2000 and Threads.owns_run?(run.id, run.attempt) do
      query = query |> String.trim() |> String.downcase()
      terms = query |> String.split() |> Enum.uniq()

      matches =
        tools
        |> Enum.map(fn {remote, tool} ->
          text =
            String.downcase(
              tool.name <> " " <> tool.description <> " " <> Jason.encode!(tool.parameters)
            )

          {tool, query in [String.downcase(remote), tool.name],
           Enum.count(terms, &String.contains?(text, &1))}
        end)
        |> Enum.filter(fn {_, _, score} -> score > 0 end)
        |> Enum.sort_by(fn {tool, exact, score} -> {not exact, -score, tool.name} end)

      page =
        matches
        |> Enum.slice(offset, 5)
        |> Enum.map(fn {tool, _, _} ->
          %{name: tool.name, description: tool.description, inputSchema: tool.parameters}
        end)

      {:ok,
       Jason.encode!(%{
         tools: page,
         next_offset: if(length(matches) > offset + 5, do: offset + 5)
       })}
    else
      {:error, :stale_run}
    end
  end

  defp search(_, _, _), do: {:error, :invalid_arguments}

  def tool_error(category),
    do:
      {:ok,
       Jason.encode!(%{isError: true, content: [%{type: "text", text: Atom.to_string(category)}]})}

  defp fingerprint(value),
    do: :sha256 |> :crypto.hash(:erlang.term_to_binary(value)) |> Base.encode16(case: :lower)
end
