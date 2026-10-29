defmodule Atlas.Orbit.EnvironmentTools do
  @moduledoc "Owner-private executor tools, independent of delivery transport or provider. Never used by MCP or research children."

  alias Atlas.Environments
  alias Atlas.Environments.Environment
  alias Atlas.Repo

  @legacy ~w(environment_list_directory environment_read_file environment_terminal)
  @coding ~w(read bash edit write)
  def names, do: @legacy ++ @coding
  def remote?(name), do: name in names()
  def coding?(name), do: name in @coding
  def terminal?(name), do: name in ~w(environment_terminal bash)
  def mutating?(name), do: name in ~w(environment_terminal bash edit write)

  def available(thread, run, parent_message_id) do
    environment = run.environment_id && Repo.get(Environment, run.environment_id)

    if is_nil(parent_message_id) and thread.kind == "private" and thread.owner_id == run.acting_user_id and
         project_available?(environment, thread.owner_id, run.project_id) do
      project = Enum.find(environment.projects, &(&1["id"] == run.project_id))

      if project["coding"] == true and environment.terminal do
        Enum.map(@coding, &descriptor/1)
      else
        Enum.filter(@legacy, &(&1 != "environment_terminal" or environment.terminal)) |> Enum.map(&descriptor/1)
      end
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

  def valid_args?("read", args) do
    fields?(args, ~w(path), ~w(offset limit)) and text?(args["path"], 1, 4_096) and
      integer?(args, "offset", 1, 1_000_000) and integer?(args, "limit", 1, 2_000)
  end

  def valid_args?("bash", args) do
    fields?(args, ~w(command), ~w(timeout)) and text?(args["command"], 1, 8_000) and
      integer?(args, "timeout", 1, 1_800)
  end

  def valid_args?("write", args) do
    fields?(args, ~w(path content)) and text?(args["path"], 1, 4_096) and text?(args["content"], 0, 65_536)
  end

  def valid_args?("edit", args) do
    fields?(args, ~w(path edits)) and text?(args["path"], 1, 4_096) and edits?(args["edits"])
  end

  def valid_args?(name, args) when name in @legacy do
    key = if name == "environment_terminal", do: "command", else: "path"
    limit = if key == "command", do: 8_000, else: 4_096

    Environments.exact_keys?(args, [key]) and is_binary(args[key]) and String.valid?(args[key]) and
      byte_size(args[key]) in 1..limit and not String.contains?(args[key], <<0>>)
  end

  def valid_args?(_name, _args), do: false

  defp fields?(args, required, optional \\ []) do
    is_map(args) and Enum.all?(required, &Map.has_key?(args, &1)) and
      Enum.all?(Map.keys(args), &(&1 in (required ++ optional)))
  end

  defp text?(value, minimum, maximum) do
    is_binary(value) and String.valid?(value) and byte_size(value) in minimum..maximum and
      not String.contains?(value, <<0>>)
  end

  defp integer?(args, key, minimum, maximum) do
    not Map.has_key?(args, key) or (is_integer(args[key]) and args[key] in minimum..maximum)
  end

  defp edits?(edits) when is_list(edits) and length(edits) in 1..16 do
    Enum.all?(edits, fn edit ->
      fields?(edit, ~w(oldText newText)) and text?(edit["oldText"], 1, 65_536) and text?(edit["newText"], 0, 65_536)
    end) and byte_size(JSON.encode!(edits)) <= 131_072
  end

  defp edits?(_edits), do: false

  defp descriptor(name) when name in @coding do
    {description, properties, required} =
      case name do
        "read" ->
          {"Read UTF-8 text in this thread's isolated Git worktree. Paths are relative to its root. offset is a 1-based line; limit defaults to 2000. Output is bounded to 48 KiB and reports truncation. Use bash for directory/search commands.",
           %{
             "path" => %{"type" => "string"},
             "offset" => %{"type" => "integer", "minimum" => 1, "maximum" => 1_000_000},
             "limit" => %{"type" => "integer", "minimum" => 1, "maximum" => 2_000}
           }, ~w(path)}

        "bash" ->
          {"Queue a shell command in this thread's isolated Git worktree on the selected execution environment. Returns a durable ticket, NOT a completed result. Stop and wait: confirmed output automatically continues the conversation. Never poll, retry an unknown outcome or queue another mutation while waiting. Terminal access is explicitly enabled; no per-command approval. The executor determines the OS, shell and process isolation; project-relative file tools do not imply a folder sandbox for shell commands. Maximum 8000 UTF-8 bytes; timeout in seconds, maximum/default 1800. Do not push, deploy or perform external writes without the person's explicit authorization.",
           %{
             "command" => %{"type" => "string"},
             "timeout" => %{"type" => "integer", "minimum" => 1, "maximum" => 1_800}
           }, ~w(command)}

        "write" ->
          {"Create or replace a UTF-8 file in this thread's isolated Git worktree, atomically. Parent directories must exist. Path is worktree-relative; content is at most 64 KiB. Read existing files before replacing them. Never retry an unknown mutation.",
           %{"path" => %{"type" => "string"}, "content" => %{"type" => "string"}}, ~w(path content)}

        "edit" ->
          {"Apply exact text replacements atomically in a UTF-8 file in this thread's isolated Git worktree (maximum 4 MiB). Each oldText must match exactly once; edits must not overlap and all refer to the original file. CRLF is normalized for matching and preserved on write. Read before editing. Maximum 16 edits and 128 KiB JSON. Never retry an unknown mutation.",
           %{
             "path" => %{"type" => "string"},
             "edits" => %{
               "type" => "array",
               "minItems" => 1,
               "maxItems" => 16,
               "items" => %{
                 "type" => "object",
                 "properties" => %{"oldText" => %{"type" => "string"}, "newText" => %{"type" => "string"}},
                 "required" => ~w(oldText newText),
                 "additionalProperties" => false
               }
             }
           }, ~w(path edits)}
      end

    %{
      "name" => name,
      "description" => description,
      "inputSchema" => %{
        "type" => "object",
        "properties" => properties,
        "required" => required,
        "additionalProperties" => false
      }
    }
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
           "Queue a durable terminal job and promptly return its ticket. Terminal access is explicitly enabled on the selected execution environment; no per-command approval is required. A confirmed result automatically continues the conversation; do not poll, retry or reserve another job while waiting. Starts in the selected project using the executor's OS and shell; a project boundary is not a folder sandbox for commands. Maximum 8,000 UTF-8 bytes; execution limit 1,800 seconds. Never retry an unknown outcome."}
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
