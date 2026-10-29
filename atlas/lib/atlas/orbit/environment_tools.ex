defmodule Atlas.Orbit.EnvironmentTools do
  @moduledoc "Personal-device exception to the read-only Atlas tools. Never used by MCP or research children."

  alias Atlas.Environments
  alias Atlas.Environments.Environment
  alias Atlas.Repo

  @names ~w(environment_list_directory environment_read_file environment_terminal)
  def names, do: @names
  def remote?(name), do: name in @names

  def available(thread, run, parent_message_id) do
    environment = run.environment_id && Repo.get(Environment, run.environment_id)

    if is_nil(parent_message_id) and thread.kind == "private" and thread.owner_id == run.acting_user_id and
         project_available?(environment, thread.owner_id, run.project_id) do
      Enum.filter(@names, &(&1 != "environment_terminal" or environment.terminal)) |> Enum.map(&descriptor/1)
    else
      []
    end
  end

  defp project_available?(nil, _owner_id, _project_id), do: false
  defp project_available?(_environment, _owner_id, nil), do: false

  defp project_available?(environment, owner_id, project_id) do
    environment.owner_id == owner_id and environment.enabled and
      Enum.any?(environment.projects, &(&1["id"] == project_id))
  end

  def valid_args?(name, args) do
    key = if name == "environment_terminal", do: "command", else: "path"
    limit = if key == "command", do: 8_000, else: 4_096

    Environments.exact_keys?(args, [key]) and is_binary(args[key]) and String.valid?(args[key]) and
      byte_size(args[key]) in 1..limit and not String.contains?(args[key], <<0>>)
  end

  defp descriptor(name) do
    {key, description} =
      case name do
        "environment_list_directory" ->
          {"path", "List directory metadata inside the selected personal project. Use a project-relative path."}

        "environment_read_file" ->
          {"path", "Read bounded UTF-8 text inside the selected personal project. Use a project-relative path."}

        "environment_terminal" ->
          {"command",
           "Queue a durable terminal job and promptly return its ticket. Terminal access is explicitly enabled on the selected Mac; no per-command approval is required. A confirmed result automatically continues the conversation; do not poll, retry or reserve another job while waiting. Runs as the macOS user starting in the selected project, without a folder sandbox. Maximum 8,000 UTF-8 bytes; execution limit 1,800 seconds. Never retry an unknown outcome."}
      end

    %{
      "name" => name,
      "description" => description,
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{key => %{"type" => "string"}},
        "required" => [key],
        "additionalProperties" => false
      }
    }
  end
end
