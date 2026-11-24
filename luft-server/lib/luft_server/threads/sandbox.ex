defmodule LuftServer.Threads.Sandbox do
  @moduledoc """
  A `Condukt.Sandbox` on a Tuist sandbox, so a thread's session runs
  Condukt's built-in Read, Write, Edit, Glob, Grep, Ls and Bash tools in the
  thread's VM.

  Files and short commands go through `Sandboxes.exec/3`. File paths are
  relative to the working directory (`:cwd`): Read, Write, Edit, Glob, Grep
  and Ls refuse other absolute paths, `..` and `.git`, never follow a symlink
  out of it, and a
  write validates its target before truncating it (see `@files`). Bash is a
  shell in the VM and is not confined. Processes, which a
  parked Bash call follows and a deploy leaves running, are
  `Tuist.Sandboxes.Commands`: detached in the guest, with offset reads that
  wait for output, stdin, and a row that records how they ended. Their
  stderr goes to stdout, since the model reads one log. A command runs under
  the run's own residency (`:residency`), not the shared `commands` one: the
  run already holds the sandbox, and its turn would otherwise refuse the
  command as `:busy`.

  `activity/2` keeps that residency while the session's turn runs or is
  parked and ends it when the turn ends; `watch_process/3` persists a watch
  for Luft's leased agent runner (`LuftServer.Threads.ExitWatchWorker`) to deliver a parked Bash call's
  exit to the session, wherever it runs then.

  Options: `:sandbox_id` and `:account_id` (both required: the row must
  belong to the account), `:residency` (the run's residency work id),
  `:cwd` (default `/workspace/repository`), `:commands_end_by`, a time in
  Unix milliseconds that every process's timeout is cut to end by, so that
  a command ends within the run that started it, and `:run` (`id`,
  `thread_id` and `attempt`), the run whose Bash calls' build and test
  progress reading a command records (`Threads.record_build_progress/3`):
  every command sets `STRUO_PROGRESS`, so a Struo build or test in it reports
  as it goes; and `:progress_interval` (default 1000), how many milliseconds
  a reading process waits before reporting an unchanged snapshot again.

  Not implemented, because the sandbox node has nothing for them yet:
  `snapshot/2` (project snapshots keyed for threads) and `expose_port/3`
  (port exposure). PTYs use util-linux `script` in the guest.
  """

  @behaviour Condukt.Sandbox

  alias Condukt.Sandbox.Processes
  alias LuftServer.Threads
  alias LuftServer.Threads.Capabilities
  alias LuftServer.Threads.ExitWatchWorker

  require Logger

  @default_cwd "/workspace/repository"
  @exec_timeout_ms 120_000
  @file_timeout_ms 30_000
  # What one exec returns per stream, and about what its environment holds.
  @max_file_bytes 1024 * 1024
  @env_part_bytes 64 * 1024
  @default_read_bytes 64 * 1024
  @past_end 4_611_686_018_427_387_904

  # Files open relative to the checkout (the exec's cwd), one directory
  # descriptor at a time with O_NOFOLLOW, so neither a symlinked parent nor a
  # symlinked final component leads out of it. A write opens the file without
  # truncating and validates it (a regular file with one link) before it
  # writes, so a symlink or hard link to a file elsewhere is never changed.
  # This is the descriptor-relative helper the original workspace used
  # for its own file tools; the content comes base64-encoded in
  # `CONDUKT_DATA_<n>` environment parts, and parents are created as needed.
  @files ~S"""
  import base64, errno, os, stat, sys
  op, path, limit = sys.argv[1], sys.argv[2], int(sys.argv[3])
  parts = path.split('/')
  if path.startswith('/') or any(p in ('', '.', '..', '.git') for p in parts):
      sys.exit(2)
  try:
      fd = os.open('.', os.O_RDONLY | os.O_DIRECTORY)
      for part in parts[:-1]:
          if op == 'write':
              try: os.mkdir(part, 0o755, dir_fd=fd)
              except FileExistsError: pass
          nxt = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd)
          os.close(fd)
          fd = nxt
      flags = os.O_NOFOLLOW | os.O_NONBLOCK
      flags |= os.O_RDONLY if op == 'read' else os.O_RDWR | os.O_CREAT
      file = os.open(parts[-1], flags, 0o644, dir_fd=fd)
      st = os.fstat(file)
      if stat.S_ISDIR(st.st_mode): raise IsADirectoryError(errno.EISDIR, path)
      if not stat.S_ISREG(st.st_mode) or st.st_nlink != 1: sys.exit(2)
      if op == 'read':
          data = b''
          while len(data) <= limit:
              chunk = os.read(file, limit + 1 - len(data))
              if not chunk: break
              data += chunk
          if len(data) > limit: sys.exit(3)
          sys.stdout.buffer.write(data)
      else:
          chunks, n = [], 0
          while 'CONDUKT_DATA_%d' % n in os.environ:
              chunks.append(os.environ['CONDUKT_DATA_%d' % n])
              n += 1
          data = base64.b64decode(''.join(chunks))
          os.lseek(file, 0, os.SEEK_SET)
          rest = data
          while rest:
              rest = rest[os.write(file, rest):]
          os.ftruncate(file, len(data))
      os.close(file)
      os.close(fd)
  except OSError as e:
      sys.stderr.write(errno.errorcode.get(e.errno, 'EIO'))
      sys.exit(1)
  """

  # Glob and grep walk the checkout from a base opened the same way, with
  # `os.fwalk`, which does not descend into symlinked directories, and open
  # each file they read with O_NOFOLLOW. `.git` is skipped. A pattern
  # matches paths relative to the base: `**/` any directories, `*` and `?`
  # within one component, `[...]` and `{a,b}`. Grep's file glob without a
  # `/` matches a file's name at any depth, as ripgrep's does.
  @walk ~S"""
  import errno, json, os, re, stat, sys

  def translate(pattern):
      out, i, depth = '', 0, 0
      while i < len(pattern):
          c = pattern[i]
          if pattern.startswith('**/', i): out += '(?:.*/)?'; i += 3; continue
          if pattern.startswith('**', i): out += '.*'; i += 2; continue
          if c == '*': out += '[^/]*'
          elif c == '?': out += '[^/]'
          elif c == '[' and ']' in pattern[i + 2:]:
              end = pattern.index(']', i + 2)
              body = pattern[i + 1:end]
              out += '[' + ('^' + body[1:] if body.startswith('!') else body).replace('\\', '\\\\') + ']'
              i = end
          elif c == '{': out += '(?:'; depth += 1
          elif c == '}' and depth: out += ')'; depth -= 1
          elif c == ',' and depth: out += '|'
          else: out += re.escape(c)
          i += 1
      return re.compile(out + ')' * depth + r'\Z', re.S)

  def walk(base):
      fd = os.open('.', os.O_RDONLY | os.O_DIRECTORY)
      for part in base.split('/') if base else []:
          nxt = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd)
          os.close(fd)
          fd = nxt
      for top, dirs, files, dir_fd in os.fwalk('.', dir_fd=fd):
          dirs[:] = sorted(d for d in dirs if d != '.git')
          rel = '' if top == '.' else os.path.normpath(top) + '/'
          yield rel, dirs, sorted(files), dir_fd

  def glob(base, pattern, limit):
      regex, out = translate(pattern), []
      for rel, dirs, files, _ in walk(base):
          out += [rel + name for name in dirs + files if regex.match(rel + name)]
      out.sort()
      return out[:limit] if limit else out

  def grep(base, pattern, file_glob, case_sensitive, limit):
      regex = re.compile(pattern, 0 if case_sensitive == '1' else re.IGNORECASE)
      names = translate(file_glob)
      by_name = '/' not in file_glob
      out = []
      for rel, _, files, dir_fd in walk(base):
          for name in files:
              if len(out) >= limit: return out
              if not names.match(name if by_name else rel + name): continue
              try:
                  file = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=dir_fd)
              except OSError:
                  continue
              st = os.fstat(file)
              if not stat.S_ISREG(st.st_mode) or st.st_nlink != 1:
                  os.close(file)
                  continue
              with os.fdopen(file, encoding='utf-8', errors='replace') as f:
                  for n, line in enumerate(f, 1):
                      if regex.search(line):
                          out.append({'path': rel + name, 'line_number': n, 'line': line.rstrip('\n')})
                          if len(out) >= limit: return out
      return out

  def ls(base):
      fd = os.open('.', os.O_RDONLY | os.O_DIRECTORY)
      for part in base.split('/') if base else []:
          nxt = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd)
          os.close(fd)
          fd = nxt
      with os.scandir(fd) as entries:
          return [{'name': e.name, 'dir': e.is_dir(follow_symlinks=False)} for e in entries if e.name != '.git']

  try:
      if sys.argv[1] == 'glob':
          print(json.dumps(glob(sys.argv[2], sys.argv[3], int(sys.argv[4]))))
      elif sys.argv[1] == 'ls':
          print(json.dumps(ls(sys.argv[2])))
      else:
          print(json.dumps(grep(sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5], int(sys.argv[6]))))
  except OSError as e:
      sys.stderr.write(errno.errorcode.get(e.errno, 'EIO'))
      sys.exit(1)
  """

  @impl true
  def init(opts) do
    with {:ok, sandbox_id} <- Keyword.fetch(opts, :sandbox_id),
         {:ok, account_id} <- Keyword.fetch(opts, :account_id),
         {:ok, owner} <- Keyword.fetch(opts, :owner),
         {:ok, %{account_id: ^account_id}} <-
           Capabilities.sandbox(owner, "show", %{sandbox_id: sandbox_id}) do
      {:ok,
       %{
         sandbox_id: sandbox_id,
         account_id: account_id,
         owner: owner,
         residency: Keyword.get(opts, :residency),
         cwd: Keyword.get(opts, :cwd, @default_cwd),
         commands_end_by: Keyword.get(opts, :commands_end_by),
         run: Keyword.get(opts, :run),
         progress_interval: Keyword.get(opts, :progress_interval, 1_000)
       }}
    else
      _ -> {:error, :sandbox_not_found}
    end
  end

  @impl true
  def shutdown(_state), do: :ok

  @impl true
  def cwd(state), do: state.cwd

  @impl true
  def read_file(state, path) do
    with {:ok, path} <- check_path(state, path) do
      files(state, ["read", path, Integer.to_string(@max_file_bytes)], %{}, raw_output: true)
    end
  end

  # The content travels base64-encoded in environment variables, in parts
  # under Linux's 128 KiB limit for one.
  @impl true
  def write_file(_state, _path, content) when byte_size(content) > @max_file_bytes,
    do: {:error, :too_large}

  def write_file(state, path, content) do
    encoded = Base.encode64(content)

    env =
      if encoded == "",
        do: %{},
        else:
          for(
            {at, index} <- Enum.with_index(0..(byte_size(encoded) - 1)//@env_part_bytes),
            into: %{},
            do:
              {"CONDUKT_DATA_#{index}",
               binary_part(encoded, at, min(@env_part_bytes, byte_size(encoded) - at))}
          )

    with {:ok, path} <- check_path(state, path),
         {:ok, _empty} <-
           files(state, ["write", path, Integer.to_string(@max_file_bytes)], env, []) do
      :ok
    end
  end

  @impl true
  def edit_file(state, path, old_text, new_text) do
    with {:ok, content} <- read_file(state, path) do
      case length(:binary.matches(content, old_text)) do
        1 ->
          [before, rest] = :binary.split(content, old_text)
          updated = before <> new_text <> rest

          with :ok <- write_file(state, path, updated),
               do: {:ok, %{occurrences: 1, content: updated}}

        count ->
          {:ok, %{occurrences: count, content: content}}
      end
    end
  end

  @impl true
  def exec(state, command, opts) do
    timeout = Keyword.get(opts, :timeout, @exec_timeout_ms)

    case run(state, ["/bin/bash", "-c", command], timeout, cwd: opts[:cwd], env: env(opts[:env])) do
      {:ok, %{exit_code: nil}} ->
        {:error, :timeout}

      {:ok, %{exit_code: code, stdout: stdout, stderr: stderr}} ->
        {:ok, %{output: stdout <> stderr, exit_code: code}}

      {:error, :timeout} ->
        {:error, :timeout}

      error ->
        error
    end
  end

  @impl true
  def glob(state, pattern, opts) do
    with {:ok, base} <- base(state, opts[:cwd]) do
      json(state, ["glob", base, pattern, to_string(opts[:limit] || 0)])
    end
  end

  @impl true
  def grep(state, pattern, opts) do
    flags = if Keyword.get(opts, :case_sensitive, true), do: "1", else: "0"

    with {:ok, base} <- base(state, opts[:path]),
         args = [
           base,
           pattern,
           Keyword.get(opts, :glob, "**/*"),
           flags,
           to_string(Keyword.get(opts, :limit, 1_000))
         ],
         {:ok, matches} <- json(state, ["grep" | args]) do
      {:ok,
       Enum.map(matches, &%{path: &1["path"], line_number: &1["line_number"], line: &1["line"]})}
    end
  end

  # Opened like glob's base, so a symlink is listed as a file, never followed.
  @impl true
  def list_dir(state, path) do
    with {:ok, base} <- base(state, path),
         {:ok, entries} <- json(state, ["ls", base]) do
      {:ok,
       Enum.map(entries, &%{name: &1["name"], type: if(&1["dir"], do: :directory, else: :file)})}
    end
  end

  # ===========================================================================
  # Processes, on `Commands`
  # ===========================================================================

  @impl true
  def start_process(state, id, command, opts) do
    command_id = command_id(id)

    with {:ok, timeout} <- process_timeout(opts[:timeout], state.commands_end_by),
         {:ok, sandbox} <- fetch(state) do
      params = %{
        command: "exec 2>&1\n" <> Processes.command(command, opts),
        env: env(opts[:env]),
        cwd: path(state, opts[:cwd]),
        stdin: Keyword.get(opts, :stdin, false),
        residency: state.residency
      }

      params = if timeout, do: Map.put(params, :timeout_ms, timeout), else: params

      case Capabilities.command(sandbox, "command_start", command_id, params) do
        {:ok, _command} -> :ok
        {:error, reason} -> {:error, reason}
      end
    end
  end

  # Cut to end before the run does. A command that would have under a
  # second is not started: it would be killed before it did anything.
  defp process_timeout(timeout, nil), do: {:ok, timeout}

  defp process_timeout(timeout, end_by) do
    case end_by - System.os_time(:millisecond) do
      left when left < 1_000 -> {:error, :run_ending}
      left -> {:ok, if(timeout, do: min(timeout, left), else: left)}
    end
  end

  @impl true
  def read_process(state, id, offset, opts) do
    read_opts = [
      stdout_offset: offset,
      # Past any output: stderr is folded into stdout.
      stderr_offset: @past_end,
      max_bytes: Keyword.get(opts, :max_bytes, @default_read_bytes),
      wait_seconds: opts |> Keyword.get(:wait, 0) |> div(1000)
    ]

    with {:ok, sandbox} <- fetch(state),
         {:ok, read} <-
           Capabilities.command(sandbox, "command_read", command_id(id), Map.new(read_opts)) do
      report_progress(state, id, read)

      {:ok,
       %{
         output: read.stdout,
         offset: read.stdout_offset,
         size: read.stdout_size,
         status: status(read)
       }}
    end
  end

  # A Bash call's process id ends in the model's id for the call
  # (`Condukt.Tools.Bash.process_id/2`, with the run's session id), which is
  # how the build progress a Struo run in it reported finds the call.
  # Progress is best effort: failing to record it must not fail reading the
  # command, which the Bash tool and its watcher depend on.
  #
  # A command's watcher reads it every few hundred milliseconds, and Struo
  # rewrites its snapshot at most once a second, mostly with only the clock
  # moved on, so the reading process skips a snapshot it reported less than
  # `:progress_interval` milliseconds ago. Reporting it again soon after
  # lets counts the server held back (`Threads.record_build_progress/3`)
  # show within its own interval while a target runs long.
  defp report_progress(%{run: %{thread_id: thread_id, id: run_id} = run} = state, id, %{
         progress: %{} = snapshot
       }) do
    seen = Map.delete(snapshot, "elapsed_ms")
    now = System.monotonic_time(:millisecond)
    reported = Process.get({__MODULE__, :progress, id})

    with ["", invocation_id] <- String.split(id, "condukt-bash:#{thread_id}:#{run_id}:", parts: 2),
         false <- reported_recently?(reported, seen, now - state.progress_interval) do
      Process.put({__MODULE__, :progress, id}, {seen, now})
      Threads.record_build_progress(run, invocation_id, snapshot)
    else
      _ -> :ok
    end
  rescue
    error ->
      Logger.warning("Could not record build progress: #{Exception.message(error)}")
      :ok
  end

  defp report_progress(_state, _id, _read), do: :ok

  defp reported_recently?({seen, at}, seen, since), do: at > since
  defp reported_recently?(_reported, _seen, _since), do: false

  # Kills the command and forgets it, so its id starts afresh, as stopping
  # does on every Condukt sandbox. Its guest log goes with the sandbox.
  @impl true
  def stop_process(state, id) do
    command_id = command_id(id)

    with {:ok, sandbox} <- fetch(state) do
      case Capabilities.command(sandbox, "command_cancel", command_id) do
        {:error, :not_found} -> :ok
        {:error, reason} -> {:error, reason}
        {:ok, _command} -> forget(sandbox, command_id)
      end
    end
  end

  @impl true
  def write_process(state, id, data, opts) do
    with {:ok, sandbox} <- fetch(state) do
      case Capabilities.command(sandbox, "command_stdin", command_id(id), %{
             data: data,
             close: Keyword.get(opts, :close, false),
             offset: opts[:offset]
           }) do
        {:ok, _command} -> :ok
        {:error, :stdin_offset_mismatch} -> {:error, :offset_mismatch}
        {:error, :stdin_not_attached} -> {:error, :stdin_closed}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @impl true
  def watch_process(state, id, %{session_id: session_id, signal: signal, key: key}) do
    ExitWatchWorker.enqueue(%{
      sandbox_id: state.sandbox_id,
      account_id: state.account_id,
      owner: state.owner,
      command_id: command_id(id),
      session_id: session_id,
      signal: Atom.to_string(signal),
      key: key
    })
  end

  # The run's residency, held while its turn runs or is parked. Joining it
  # again renews it; a turn that ends gives it back, and the run releasing
  # its workspace ends it too.
  @impl true
  def activity(%{residency: nil}, _activity), do: :ok

  def activity(state, :active) do
    with {:ok, sandbox} <- fetch(state),
         {:ok, _held} <-
           Capabilities.sandbox(sandbox.owner, "renew", %{
             sandbox_id: sandbox.id,
             work_id: state.residency
           }),
         do: :ok
  end

  def activity(state, :idle) do
    case Capabilities.request(state.owner, "release", %{
           sandbox_id: state.sandbox_id,
           work_id: state.residency
         }) do
      {:ok, _} -> :ok
      error -> error
    end
  end

  @doc """
  The `sandbox_commands` id of a Condukt process id: a UUID derived from it,
  so the same id finds the same command after a restart.
  """
  def command_id(id) do
    <<a::32, b::16, _::4, c::12, _::2, d::62, _::binary>> = :crypto.hash(:sha256, id)

    <<a::32, b::16, 8::4, c::12, 2::2, d::62>>
    |> Ecto.UUID.load()
    |> then(fn {:ok, uuid} -> uuid end)
  end

  @doc false
  # What `Condukt.Sandbox.read_process/4` reports for a command's read.
  def status(%{status: "running"}), do: :running
  def status(%{status: "timed_out"}), do: :timeout
  def status(%{status: "lost"}), do: {:exited, nil}
  def status(%{exit_code: code}), do: {:exited, code}

  defp forget(sandbox, command_id) do
    case Capabilities.command(sandbox, "command_forget", command_id) do
      {:ok, _} -> :ok
      error -> error
    end
  end

  defp fetch(state) do
    with true <- owns_run?(state.run),
         {:ok, %{account_id: account_id} = sandbox} when account_id == state.account_id <-
           Capabilities.sandbox(state.owner, "show", %{sandbox_id: state.sandbox_id}) do
      {:ok, sandbox}
    else
      _ -> {:error, :sandbox_not_found}
    end
  end

  defp run(state, argv, timeout, opts) do
    with {:ok, sandbox} <- fetch(state) do
      exec_opts =
        opts
        |> Keyword.put(:cwd, path(state, opts[:cwd]))
        |> Keyword.update(:env, %{}, &(&1 || %{}))
        |> Keyword.put(:timeout_ms, timeout)

      Capabilities.exec(sandbox, argv, Keyword.take(exec_opts, [:cwd, :env, :timeout_ms]))
    end
  end

  defp files(state, args, env, opts) do
    case run(
           state,
           ["python3", "-c", @files | args],
           @file_timeout_ms,
           Keyword.put(opts, :env, env)
         ) do
      {:ok, %{exit_code: 0, stdout: stdout}} -> {:ok, stdout}
      {:ok, result} -> {:error, file_error(result)}
      error -> error
    end
  end

  defp json(state, args) do
    case run(state, ["python3", "-c", @walk | args], @file_timeout_ms, []) do
      {:ok, %{exit_code: 0, stdout: stdout}} -> JSON.decode(stdout)
      {:ok, result} -> {:error, file_error(result)}
      error -> error
    end
  end

  # A path in the checkout, made relative to it: an absolute path under the
  # checkout and a `./` prefix are taken, as the tools describe paths. No
  # other absolute paths, no `.` or `..` components, nothing under `.git`.
  # The guest helpers check again.
  defp check_path(state, path) do
    path =
      if is_binary(path),
        do: Regex.replace(~r{\A(\./)+}, String.replace_prefix(path, state.cwd <> "/", ""), ""),
        else: path

    if is_binary(path) and String.valid?(path) and byte_size(path) <= 4096 and
         not String.contains?(path, <<0>>) and
         not String.starts_with?(path, "/") and
         Enum.all?(String.split(path, "/"), &(&1 not in ["", ".", "..", ".git"])),
       do: {:ok, path},
       else: {:error, :invalid_path}
  end

  # Glob's and grep's base directory: the checkout, or a directory in it.
  defp base(_state, nil), do: {:ok, ""}

  defp base(state, path) do
    base = String.trim_trailing(path, "/")
    if base in ["", "."] or base == state.cwd, do: {:ok, ""}, else: check_path(state, base)
  end

  defp path(state, nil), do: state.cwd
  defp path(state, path), do: Path.expand(path, state.cwd)

  defp env(nil), do: %{}
  defp env(env), do: Map.new(env, fn {key, value} -> {to_string(key), to_string(value)} end)

  defp file_error(%{exit_code: 2}), do: :invalid_path
  defp file_error(%{exit_code: 3}), do: :too_large

  defp file_error(%{stderr: stderr}) do
    case String.trim(stderr) do
      "ENOENT" -> :enoent
      "EISDIR" -> :eisdir
      "ENOTDIR" -> :enotdir
      "EACCES" -> :eacces
      "ELOOP" -> :symlink
      other -> other
    end
  end

  defp owns_run?(%{id: id, attempt: attempt}), do: Threads.owns_run?(id, attempt)
  defp owns_run?(_), do: false
end
