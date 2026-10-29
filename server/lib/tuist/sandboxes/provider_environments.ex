defmodule Tuist.Sandboxes.ProviderEnvironments do
  @moduledoc "Identity-scoped hosted workspaces. Lifecycle generations fence delayed provider calls."

  import Ecto.Query

  alias Tuist.Accounts.Account
  alias Tuist.FeatureFlags
  alias Tuist.Repo
  alias Tuist.Sandboxes
  alias Tuist.Sandboxes.ProviderEnvironment
  alias Tuist.Sandboxes.Sandbox

  # Open each component relative to a directory descriptor, without following
  # symlinks. Neither traversal nor a concurrent symlink replacement can escape.
  @files """
  import os, sys, stat, itertools
  path = sys.argv[2]
  if path.startswith('/') or '..' in path.split('/'):
      sys.exit('Use a workspace-relative path without parent traversal.')
  fd = os.open('/workspace', os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
  for part in path.split('/'):
      if part not in ('', '.'):
          next_fd = os.open(part, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=fd)
          os.close(fd)
          fd = next_fd
  if sys.argv[1] == 'environment_list_directory':
      with os.scandir(fd) as entries:
          for entry in itertools.islice(entries, 200):
              print(entry.name)
  else:
      if not stat.S_ISREG(os.fstat(fd).st_mode):
          sys.exit('Only regular files may be read.')
      data = os.read(fd, 60000)
      print(data.decode('utf-8', errors='replace'))
  os.close(fd)
  """

  def dispatch(account, key, operation, params) do
    generation = params["generation"]

    if is_integer(generation) and generation in 1..9_223_372_036_854_775_807 and valid_operation?(operation, params) do
      # Same cluster membership contract as Sandboxes.with_sandbox_lock. This
      # identity lock also covers creation, before a sandbox ID exists.
      :global.trans(
        {{__MODULE__, account.id, key}, self()},
        fn ->
          with :ok <- enabled(account, operation),
               {:ok, binding} <- binding(account, key, operation) do
            run(account, binding, operation, generation, params)
          end
        end,
        [node() | Node.list()]
      )
    else
      {:error, :invalid_params}
    end
  end

  defp valid_operation?(:exec, params), do: match?({:ok, _, _}, command(params))
  defp valid_operation?(operation, params) when operation in [:start, :pause, :delete], do: exact?(params, ~w(generation))
  defp valid_operation?(_, _), do: false

  defp enabled(account, operation) when operation in [:start, :exec] do
    if FeatureFlags.sandboxes_enabled?(account), do: :ok, else: {:error, :disabled}
  end

  defp enabled(_account, _operation), do: :ok

  defp binding(account, key, operation) do
    case Repo.get_by(ProviderEnvironment, account_id: account.id, external_key: key) do
      nil when operation == :exec ->
        {:error, :unavailable}

      nil ->
        Repo.transaction(fn ->
          Repo.one!(from a in Account, where: a.id == ^account.id, lock: "FOR NO KEY UPDATE")

          if Repo.aggregate(from(e in ProviderEnvironment, where: e.account_id == ^account.id), :count) >= 4096,
            do: Repo.rollback(:environment_limit)

          Repo.insert!(%ProviderEnvironment{account_id: account.id, external_key: key})
        end)

      binding ->
        {:ok, binding}
    end
  end

  defp run(_account, binding, _operation, generation, _params) when generation < binding.generation,
    do: {:error, :stale_generation}

  defp run(account, binding, :start, generation, params) do
    cond do
      not exact?(params, ~w(generation)) ->
        {:error, :invalid_params}

      not FeatureFlags.sandboxes_enabled?(account) ->
        {:error, :disabled}

      generation == binding.generation and not binding.enabled ->
        {:error, :stale_generation}

      true ->
        binding = update_binding!(binding, generation, true)
        sandbox = Repo.get_by(Sandbox, provider_environment_id: binding.id)

        result =
          case sandbox do
            nil -> Sandboxes.create_sandbox(account, %{provider_environment_id: binding.id})
            sandbox -> Sandboxes.ensure_running(sandbox)
          end

        with {:ok, _} <- result, do: {:ok, %{state: "ready"}}
    end
  end

  defp run(_account, binding, operation, generation, params) when operation in [:pause, :delete] do
    if exact?(params, ~w(generation)) do
      update_binding!(binding, generation, false)
      sandbox = Repo.get_by(Sandbox, provider_environment_id: binding.id)

      result =
        case {operation, sandbox} do
          {_, nil} -> {:ok, nil}
          {:pause, %Sandbox{state: :paused}} -> {:ok, nil}
          {:pause, sandbox} -> Sandboxes.pause(sandbox)
          {:delete, sandbox} -> Sandboxes.delete(sandbox)
        end

      with {:ok, _} <- result, do: {:ok, %{state: if(operation == :pause, do: "paused", else: "deleted")}}
    else
      {:error, :invalid_params}
    end
  end

  defp run(account, binding, :exec, generation, params) do
    with true <- binding.enabled and generation == binding.generation,
         true <- FeatureFlags.sandboxes_enabled?(account),
         {:ok, argv, timeout} <- command(params),
         %Sandbox{} = sandbox <- Repo.get_by(Sandbox, provider_environment_id: binding.id),
         {:ok, result} <- Sandboxes.exec(sandbox, argv, timeout_ms: timeout * 1000, cwd: "/workspace") do
      output = bounded(result.stdout <> result.stderr)
      {:ok, %{success: result.exit_code == 0, output: output}}
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :unavailable}
    end
  end

  defp update_binding!(binding, generation, enabled) do
    binding |> Ecto.Changeset.change(generation: generation, enabled: enabled) |> Repo.update!()
  end

  defp command(params) do
    with true <- exact?(params, ~w(generation id tool arguments execution_timeout_seconds)),
         {:ok, _} <- Ecto.UUID.cast(params["id"]),
         %{"project_id" => project_id} = args <- params["arguments"],
         {:ok, _} <- Ecto.UUID.cast(project_id) do
      case {params["tool"], params["execution_timeout_seconds"]} do
        {"environment_terminal", 600} ->
          if exact?(args, ~w(project_id command)) and text?(args["command"], 8000),
            do: {:ok, ["/bin/sh", "-lc", args["command"]], 600},
            else: {:error, :invalid_params}

        {tool, 60} when tool in ~w(environment_list_directory environment_read_file) ->
          if exact?(args, ~w(project_id path)) and text?(args["path"], 4096),
            do: {:ok, ["python3", "-c", @files, tool, args["path"]], 60},
            else: {:error, :invalid_params}

        _ ->
          {:error, :invalid_params}
      end
    else
      _ -> {:error, :invalid_params}
    end
  end

  defp text?(value, limit),
    do: is_binary(value) and String.valid?(value) and byte_size(value) in 1..limit and not String.contains?(value, <<0>>)

  defp exact?(map, keys), do: is_map(map) and Enum.sort(Map.keys(map)) == Enum.sort(keys)

  defp bounded(output) when byte_size(output) <= 65_536, do: output

  defp bounded(output),
    do: output |> binary_part(0, 65_500) |> String.replace_invalid() |> Kernel.<>("\n[Output truncated]")
end
