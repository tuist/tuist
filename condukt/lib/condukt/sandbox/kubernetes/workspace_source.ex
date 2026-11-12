defmodule Condukt.Sandbox.Kubernetes.WorkspaceSource do
  @moduledoc false

  alias Condukt.Sandbox.Kubernetes.Exec
  alias Condukt.Sandbox.Kubernetes.State

  def normalize(nil), do: {:ok, nil}

  def normalize(git) when is_binary(git) do
    if present?(git) do
      {:ok, %{git: git, ref: nil}}
    else
      {:error, ":workspace_source git URL cannot be empty"}
    end
  end

  def normalize(source) when is_list(source) do
    if Keyword.keyword?(source) do
      source
      |> Map.new()
      |> normalize()
    else
      {:error, ":workspace_source keyword options must use atom keys"}
    end
  end

  def normalize(source) when is_map(source) do
    git = Map.get(source, :git) || Map.get(source, "git")
    ref = Map.get(source, :ref) || Map.get(source, "ref")

    cond do
      not present?(git) ->
        {:error, ":workspace_source requires a non-empty git URL string or :git entry"}

      not is_nil(ref) and not present?(ref) ->
        {:error, ":workspace_source :ref must be a non-empty string when provided"}

      true ->
        {:ok, %{git: git, ref: ref}}
    end
  end

  def normalize(_other) do
    {:error, ":workspace_source must be a git URL string or keyword/map options"}
  end

  def prepare(%State{} = state, %{workspace_source: nil}), do: {:ok, state}

  def prepare(%State{} = state, config) do
    script = init_script(config.cwd, config.workspace_source)

    case Exec.run(state, ["bash", "-c", script], timeout: config.workspace_source_timeout) do
      {:ok, %{exit_code: 0}} -> {:ok, state}
      {:ok, %{output: output}} -> {:error, {:workspace_source, Exec.format_remote_error(output)}}
      {:error, reason} -> {:error, {:workspace_source, reason}}
    end
  end

  defp init_script(cwd, source) do
    ref_script = ref_script(source.ref)
    not_empty_message = "workspace #{cwd} is not empty and is not a git repository"

    """
    set -e
    cd #{Exec.shell_quote(cwd)}
    if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      #{ref_script}
      exit 0
    fi
    if [ -n "$(find . -mindepth 1 -maxdepth 1 -print -quit)" ]; then
      printf '%s\\n' #{Exec.shell_quote(not_empty_message)} >&2
      exit 73
    fi
    git clone -- #{Exec.shell_quote(source.git)} .
    #{ref_script}
    """
  end

  defp ref_script(nil), do: ":"

  defp ref_script(ref) do
    "git fetch --all --tags --prune && git -c advice.detachedHead=false checkout #{Exec.shell_quote(ref)}"
  end

  defp present?(value), do: is_binary(value) and String.trim(value) != ""
end
