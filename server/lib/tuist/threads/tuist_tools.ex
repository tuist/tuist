defmodule Tuist.Threads.TuistTools do
  @moduledoc """
  Tuist's own MCP tools (`Tuist.MCP.Server`) for a thread's run, acting as the
  person whose message started it, with that person's dashboard permissions.
  Only read-only tools (`readOnlyHint`) are offered: runs read untrusted
  content such as build logs and repositories, and nothing asks the person to
  approve a write yet.

  They run in this process rather than over HTTP: each call reloads the user,
  so one who was deleted or disabled since the run started is refused, and
  then calls the tool the way the MCP endpoint would for that user's session.
  Calls go through the run's durable external-tool reservation like profile
  MCP tools, so an effect the run cannot confirm is never repeated.
  """

  alias Tuist.Accounts
  alias Tuist.Accounts.User
  alias Tuist.Threads

  @prefix "tuist_"
  @max_result 262_144

  @doc "The tools as `{name, tool}` pairs for `Tuist.Threads.MCP.discover/3`."
  def tools(%User{id: user_id}, run) do
    for {name, module} <- Tuist.MCP.Server.server().tools, read_only?(module) do
      {name, tool(user_id, run, @prefix <> name, module)}
    end
  end

  defp tool(user_id, run, name, module) do
    Condukt.tool(
      name: name,
      description: "Tuist tool, acting as the person who sent this message. " <> module.description(),
      parameters: module.input_schema(),
      call: fn args, _context ->
        Threads.call_external_tool(run, Ecto.UUID.generate(), name, args, fn ->
          invoke(user_id, module, args)
        end)
      end
    )
  end

  defp invoke(user_id, module, args) do
    with %User{active: true, disabled_at: nil} = user <- Accounts.get_user_by_id(user_id),
         :ok <- EMCP.Tool.InputSchema.validate(module.input_schema(), args) do
      result = module.call(%Plug.Conn{assigns: %{current_user: user}}, args)
      output = JSON.encode!(Map.take(result, ["content", "structuredContent", "isError"]))
      if byte_size(output) <= @max_result, do: {:ok, output}, else: tool_error("tuist_result_too_large")
    else
      {:error, _message} -> {:error, :invalid_arguments}
      _ -> tool_error("tuist_user_unavailable")
    end
  rescue
    # Only reads are offered, so a crashed call changed nothing.
    _ -> tool_error("tuist_tool_failed")
  end

  defp read_only?(module), do: module.annotations()[:readOnlyHint] == true

  defp tool_error(category), do: {:ok, JSON.encode!(%{isError: true, content: [%{type: "text", text: category}]})}
end
