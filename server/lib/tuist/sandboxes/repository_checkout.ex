defmodule Tuist.Sandboxes.RepositoryCheckout do
  @moduledoc """
  Packages a thread's checkout on the server, so the repository's
  credentials never enter its sandbox.

  The agent's shell runs as root in the thread's sandbox before a repository
  is checked out, so nothing that runs there afterwards can be trusted with
  a token: a replaced `git`, a CA it added or a process reading environments
  would all see it. Instead the server fetches the base commit with a token
  for that one repository (`Repository.environment/3`) into a disposable bare
  repository, one commit deep, and tars it. The tar goes to the account's object
  storage as a sandbox upload (`Tuist.Sandboxes.Uploads.stage_file/3`), and
  the guest downloads it through a presigned URL that reads that one object.

  The checkout the guest builds from it is untrusted like the rest of the
  guest: what Ship relies on is the base commit the server resolved, which
  it reviews against GitHub's own trees.
  """

  alias Tuist.Sandboxes.Uploads
  alias Tuist.VCS.RepositoryBroker, as: Repository

  require Logger

  # One commit: a deeper history costs every checkout in fetch, upload and
  # download time, and the agent has no credentials to fetch more.
  @depth 1
  @max_bytes 2 * 1024 * 1024 * 1024
  # GitHub's `size` (KiB) counts the whole history, which a one-commit
  # checkout does not fetch, so it gets more headroom than the archive.
  @max_repository_kib 4 * 1024 * 1024
  @timeouts [fetch_ms: 300_000, archive_ms: 120_000]

  @doc """
  Whether an authorized repository (`Repository.authorize/2`) is small
  enough to check out, from the size GitHub reports, before the server
  fetches anything.
  """
  def fits(%{size: size}) when is_integer(size) and size > @max_repository_kib, do: {:error, :repository_too_large}
  def fits(_repository), do: :ok

  @doc """
  Fetches `base` of the account's authorized `repository` and stages it for
  `sandbox`, returning the URL the guest downloads it from. The archive is
  a tar of a bare repository holding `base` as `refs/tuist/base`, with
  `origin` pointing at the repository without credentials. `opts` bounds
  the fetch (`:fetch_ms`) and every other step (`:archive_ms`).
  """
  def stage(account, sandbox, repository, base, opts \\ []) do
    timeouts = Keyword.merge(@timeouts, opts)

    with {:ok, git} <- git(),
         {:ok, env} <- Repository.environment(account, repository, :read) do
      [directory: true]
      |> Briefly.create()
      |> case do
        {:ok, directory} ->
          try do
            package(git, directory, repository, base, env, account, sandbox, timeouts)
          after
            File.rm_rf(directory)
          end

        _ ->
          {:error, :checkout_unavailable}
      end
    end
  end

  defp package(git, directory, repository, base, env, account, sandbox, timeouts) do
    store = Path.join(directory, "repository.git")
    archive = Path.join(directory, "repository.tar")
    url = "https://github.com/#{repository}.git"
    step = timeouts[:archive_ms]

    with :ok <- run(git, ["init", "--quiet", "--bare", store], directory, %{}, step),
         :ok <- run(git, ["remote", "add", "origin", url], store, %{}, step),
         :ok <-
           run(
             git,
             ["fetch", "--quiet", "--no-tags", "--depth", "#{@depth}", "--", url, base],
             store,
             env,
             timeouts[:fetch_ms]
           ),
         :ok <- run(git, ["update-ref", "refs/tuist/base", base, ""], store, %{}, step),
         :ok <- tar(store, archive, step),
         {:ok, %{size: size}} when size <= @max_bytes <- File.stat(archive) do
      Uploads.stage_file(account, sandbox, archive)
    else
      {:ok, %File.Stat{}} -> {:error, :checkout_too_large}
      {:error, _} = error -> error
      _ -> {:error, :checkout_unavailable}
    end
  end

  # Git packs are already compressed: gzip would cost CPU and save nothing.
  defp tar(store, archive, timeout) do
    case quiet("tar", ["-cf", archive, "-C", store, "."], timeout: timeout) do
      {_, 0} ->
        :ok

      result ->
        Logger.warning("threads: archiving a checkout failed: #{inspect(elem(result, 1))}")
        {:error, :checkout_unavailable}
    end
  end

  # No inherited Git configuration or overrides; HTTPS to GitHub only. The
  # token arrives as a header in `env` and is never written to the store.
  defp run(git, args, cd, env, timeout) do
    clean =
      System.get_env()
      |> Enum.filter(fn {key, _} -> String.starts_with?(key, "GIT_") end)
      |> Map.new(fn {key, _} -> {key, nil} end)
      |> Map.merge(%{
        "GIT_CONFIG_NOSYSTEM" => "1",
        "GIT_CONFIG_GLOBAL" => "/dev/null",
        "GIT_TERMINAL_PROMPT" => "0",
        "GIT_ALLOW_PROTOCOL" => "https",
        "HOME" => cd,
        "XDG_CONFIG_HOME" => cd,
        "LC_ALL" => "C"
      })
      |> Map.merge(env)

    args = [
      "-c",
      "core.hooksPath=/dev/null",
      "-c",
      "credential.helper=",
      "-c",
      "protocol.allow=never",
      "-c",
      "protocol.https.allow=always" | args
    ]

    case quiet(git, args, cd: cd, env: clean, timeout: timeout) do
      {_, 0} ->
        :ok

      # The step and its exit status only: git's output can name URLs.
      result ->
        Logger.warning("threads: git #{Enum.at(args, 8)} failed for a checkout: #{inspect(elem(result, 1))}")
        {:error, :checkout_unavailable}
    end
  end

  # Discards the command's output in the child. MuonTrap acknowledges each
  # chunk of output to the port, and an acknowledgement sent after the command
  # exited fails with an `:epipe` exit that kills the calling process.
  defp quiet(command, args, opts) do
    MuonTrap.cmd("/bin/sh", ["-c", ~S(exec "$0" "$@" >/dev/null 2>&1), command | args], opts)
  end

  defp git do
    case System.find_executable("git") do
      nil -> {:error, :checkout_unavailable}
      git -> {:ok, git}
    end
  end
end
