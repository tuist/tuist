defmodule Tuist.Threads.Shipping do
  @moduledoc """
  Host-controlled Ship. Never registered as a model tool.

  The caller persists the complete preview before showing it, and passes only
  a database-loaded, explicitly approved record and owning run to execute/3. Approval fields:
  request_id, thread_id, account_id, repository, sandbox_id, head_sha, base_sha,
  target_branch, mode, status (:approved or :executing), approved_by_id,
  approved_at. Preview creates immutable
  Git objects only, not an index change, branch move or working-tree commit.

  On success the domain must atomically record the request result and advance
  thread.base_sha to result.head_sha. On :shipping_uncertain retain the same
  immutable approval, durably block further work, and use reconcile/2 only.
  Do not replay execute/3 after an uncertain or crashed invocation. A
  failed/uncertain Ship never repeats an agent's shell command.
  """

  alias Tuist.Accounts
  alias Tuist.Repo
  alias Tuist.Sandboxes
  alias Tuist.Sandboxes.Sandbox
  alias Tuist.Threads
  alias Tuist.Threads.Repository
  alias Tuist.Threads.Workspace

  # Hash raw files without clean filters, textconv, hooks or the user's index.
  # All file reads are relative to O_NOFOLLOW directory descriptors. Git's file
  # inventory supplies ignore semantics; removed files disappear from the tree.
  @snapshot ~S"""
  import os, sys, stat, subprocess, tempfile, hashlib
  root = '/workspace/repository'
  base, thread = sys.argv[1:3]
  env = dict(os.environ, GIT_CONFIG_NOSYSTEM='1', GIT_CONFIG_GLOBAL='/dev/null',
             GIT_AUTHOR_NAME='Tuist Threads', GIT_AUTHOR_EMAIL='threads@tuist.dev',
             GIT_COMMITTER_NAME='Tuist Threads', GIT_COMMITTER_EMAIL='threads@tuist.dev',
             GIT_AUTHOR_DATE='2000-01-01T00:00:00Z', GIT_COMMITTER_DATE='2000-01-01T00:00:00Z')
  def git(args, data=None, limit=1048576):
      with tempfile.TemporaryFile() as output:
          p = subprocess.run(['git', '-c', 'core.hooksPath=/dev/null', '-c', 'core.fsmonitor=false'] + args,
                             cwd=root, env=env, input=data, stdout=output, stderr=subprocess.DEVNULL, timeout=30)
          output.seek(0)
          result = output.read(limit + 1)
          if p.returncode or len(result) > limit: raise ValueError()
          return result
  try:
      if git(['rev-parse', '--show-toplevel']).strip() != root.encode(): raise ValueError()
      workspace = os.open('/workspace', os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
      root_fd = os.open('repository', os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=workspace)
      metadata = os.open('.git', os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=root_fd)
      os.close(metadata)
      original = {}
      for entry in git(['ls-tree', '-r', '-z', base], limit=16777216).split(b'\x00'):
          if not entry: continue
          metadata, path = entry.split(b'\t', 1)
          mode, kind, oid = metadata.decode('ascii').split()
          original[path] = (mode, kind, oid)
      paths = set(git(['ls-files', '--cached', '--others', '--exclude-standard', '-z'], limit=16777216).split(b'\x00')) - {b''}
      if len(paths) > 50000: raise ValueError()
      tree, total = {}, 0
      for raw in sorted(paths):
          parts = raw.decode('utf-8').split('/')
          if any(p in ('', '.', '..', '.git') for p in parts): raise ValueError()
          fd = os.dup(root_fd)
          try:
              try:
                  for part in parts[:-1]:
                      nxt = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd)
                      os.close(fd)
                      fd = nxt
                  info = os.stat(parts[-1], dir_fd=fd, follow_symlinks=False)
              except (FileNotFoundError, NotADirectoryError): continue
              oid = None
              if stat.S_ISDIR(info.st_mode) and original.get(raw, (None,))[0] == '160000':
                  # Preserve unchanged submodules, but never silently ship a
                  # dirty or moved submodule without its own reviewed objects.
                  git(['diff', '--quiet', '--ignore-submodules=none', base, '--', raw.decode('utf-8')])
                  mode, _, oid = original[raw]
                  data = b''
              elif stat.S_ISDIR(info.st_mode):
                  continue
              elif stat.S_ISLNK(info.st_mode):
                  data = os.readlink(parts[-1], dir_fd=fd).encode('utf-8')
                  mode = '120000'
              elif stat.S_ISREG(info.st_mode):
                  file = os.open(parts[-1], os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=fd)
                  try:
                      actual = os.fstat(file)
                      if not stat.S_ISREG(actual.st_mode) or actual.st_nlink != 1: raise ValueError()
                      digest = hashlib.sha1(('blob ' + str(actual.st_size)).encode() + b'\x00')
                      chunks, size = [], 0
                      while True:
                          chunk = os.read(file, 65536)
                          if not chunk: break
                          digest.update(chunk)
                          size += len(chunk)
                          total += len(chunk)
                          if total > 1073741824: raise ValueError()
                          if size <= 1048576: chunks.append(chunk)
                      if size != actual.st_size: raise ValueError()
                      oid = digest.hexdigest()
                      data = b''.join(chunks)
                      if size > 1048576 and original.get(raw, (None, None, None))[2] != oid: raise ValueError()
                      if size <= 1048576 and original.get(raw, (None, None, None))[2] != oid:
                          if git(['hash-object', '-w', '--stdin', '--no-filters'], data).strip().decode('ascii') != oid: raise ValueError()
                      mode = '100755' if actual.st_mode & 0o111 else '100644'
                  finally: os.close(file)
              else: raise ValueError()
              if oid is None:
                  oid = git(['hash-object', '-w', '--stdin', '--no-filters'], data).strip().decode('ascii')
              node = tree
              for part in parts[:-1]: node = node.setdefault(part, {})
              node[parts[-1]] = (mode, oid)
          finally: os.close(fd)
      def build(node):
          entries = []
          for name, value in sorted(node.items()):
              mode, kind, oid = ('040000', 'tree', build(value)) if isinstance(value, dict) else (value[0], 'commit' if value[0] == '160000' else 'blob', value[1])
              entries.append((mode + ' ' + kind + ' ' + oid + '\t' + name).encode('utf-8') + b'\x00')
          return git(['mktree', '-z'], b''.join(entries)).strip().decode('ascii')
      tree_sha = build(tree)
      print(git(['commit-tree', tree_sha, '-p', base, '-m', 'Tuist Threads ' + thread]).strip().decode('ascii'))
  except Exception:
      sys.exit(2)
  """

  # The guest exports immutable objects WITHOUT a token. All GitHub writes run
  # in the server broker, never in the agent's process or filesystem namespace.
  @export ~S"""
  import sys, subprocess, json, base64
  base, head = sys.argv[1:3]
  def git(args):
      result = subprocess.run(['git', '-c', 'core.hooksPath=/dev/null', '-c', 'core.fsmonitor=false'] + args,
                              cwd='/workspace/repository', stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=30)
      if result.returncode or len(result.stdout) > 1048576: raise ValueError()
      return result.stdout
  def tree(sha):
      result = {}
      for entry in git(['ls-tree', '-r', '-z', sha]).split(b'\x00'):
          if not entry: continue
          metadata, path = entry.split(b'\t', 1)
          mode, kind, oid = metadata.decode('ascii').split()
          result[path.decode('utf-8')] = (mode, kind, oid)
      return result
  try:
      before, after = tree(base), tree(head)
      entries, total = [], 0
      for path in sorted(set(before) | set(after)):
          if before.get(path) == after.get(path): continue
          if len(entries) >= 200: raise ValueError()
          mode, kind, oid = after.get(path, before.get(path))
          if kind != 'blob' or mode not in ('100644', '100755', '120000'): raise ValueError()
          entry = dict(path=path, mode=mode, type=kind, sha=None)
          if path in after:
              data = git(['cat-file', 'blob', oid])
              total += len(data)
              if total > 524288: raise ValueError()
              entry.update(sha=oid, content=base64.b64encode(data).decode('ascii'))
          entries.append(entry)
      output = json.dumps(dict(tree_sha=git(['rev-parse', head + '^{tree}']).strip().decode('ascii'), entries=entries))
      if len(output.encode('utf-8')) > 900000: raise ValueError()
      print(output)
  except Exception:
      sys.exit(2)
  """

  def preview(user, thread) do
    Workspace.exclusive(thread.id, fn ->
      thread = Repo.reload!(thread)

      with {:ok, account} <- Accounts.get_account_by_id(thread.account_id),
           true <- thread.owner_id == user.id,
           :ok <- Threads.authorize(user, account),
           :ok <- ready(thread),
           {:ok, repository} <- Repository.authorize(account, thread.repository) do
        request_id = Ecto.UUID.generate()

        with_residency(thread, "preview:#{thread.id}", fn sandbox ->
          snapshot_preview(account, sandbox, thread, repository, request_id)
        end)
      else
        false -> {:error, :shipping_preview_unavailable}
        {:error, _} = error -> error
      end
    end)
  end

  defp snapshot_preview(account, sandbox, thread, repository, request_id) do
    with {:ok, head} <- snapshot(sandbox, thread),
         snapshot = %{thread_id: thread.id, repository: repository.name, base_sha: thread.base_sha, head_sha: head},
         {:ok, objects} <- export_objects(sandbox, snapshot),
         {:ok, diff} <-
           Repository.review(account, snapshot, objects),
         true <- byte_size(diff) <= 131_072,
         true <- diff != "" do
      {:ok,
       %{
         request_id: request_id,
         thread_id: thread.id,
         account_id: thread.account_id,
         repository: repository.name,
         sandbox_id: sandbox.id,
         head_sha: head,
         base_sha: thread.base_sha,
         diff: diff,
         target_branch: target(thread),
         mode: thread.ship_mode,
         actor: "GitHub App installation (Tuist Threads)"
       }}
    else
      false -> {:error, :shipping_diff_empty_or_too_large}
      {:error, _} = error -> error
    end
  end

  def execute(thread, approval, run) do
    Workspace.exclusive(thread.id, fn ->
      thread = Repo.reload!(thread)

      with :ok <- approved(thread, approval),
           :ok <- owns_run(thread, approval, run),
           :ok <- ready(thread),
           {:ok, account} <- Accounts.get_account_by_id(thread.account_id),
           user when not is_nil(user) <- Accounts.get_user_by_id(approval.approved_by_id),
           :ok <- Threads.authorize(user, account),
           {:ok, _} <- Repository.authorize(account, approval.repository) do
        with_residency(thread, approval.request_id, fn sandbox ->
          publish_reviewed(account, sandbox, thread, approval, run)
        end)
      else
        {:error, _} = error -> error
        _ -> {:error, :shipping_unavailable}
      end
    end)
  end

  defp publish_reviewed(account, sandbox, thread, approval, run) do
    export = fn ->
      with :ok <- owns_run(thread, approval, run),
           {:ok, objects} <- reviewed_objects(sandbox, thread, approval),
           {:ok, diff} <- Repository.review(account, approval, objects),
           true <- diff == approval.diff do
        {:ok, objects}
      else
        false -> {:error, :shipping_review_stale}
        {:error, _} = error -> error
      end
    end

    case Repository.ship(account, approval, export, fn -> owns_run(thread, approval, run) end) do
      :ok -> success(approval)
      {:error, _} = error -> error
    end
  end

  @doc """
  Read-only positive reconciliation, including archived threads and lost VMs.
  Returns success only when GitHub currently points at the reviewed head. Every
  other observation remains uncertain: an old in-flight request may still land.
  The domain must keep outcome_unknown blocking until it records this success
  (or a human resolves the outcome). This function never resumes a ref write.
  """
  def reconcile(thread, approval) do
    Workspace.exclusive(thread.id, fn ->
      thread = Repo.reload!(thread)

      with :ok <- approved(thread, approval, true),
           {:ok, account} <- Accounts.get_account_by_id(thread.account_id),
           user when not is_nil(user) <- Accounts.get_user_by_id(approval.approved_by_id),
           :ok <- Threads.authorize(user, account),
           :ok <- Repository.reconcile(account, approval) do
        success(approval)
      else
        {:error, _} = error -> error
        _ -> {:error, :shipping_uncertain}
      end
    end)
  end

  defp reviewed_objects(sandbox, thread, approval) do
    with {:ok, head} <- snapshot(sandbox, thread),
         true <- head == approval.head_sha do
      export_objects(sandbox, approval)
    else
      false -> {:error, :shipping_review_stale}
      {:error, _} = error -> error
    end
  end

  defp export_objects(sandbox, approval) do
    with true <- Workspace.sha?(approval.base_sha) and Workspace.sha?(approval.head_sha),
         {:ok, %{exit_code: 0, stdout: output}} when byte_size(output) <= 900_000 <-
           Sandboxes.exec(sandbox, ["python3", "-c", @export, approval.base_sha, approval.head_sha],
             cwd: "/workspace",
             env: %{},
             timeout_ms: 90_000
           ),
         {:ok, objects} <- JSON.decode(output) do
      {:ok, objects}
    else
      _ -> {:error, :shipping_export_failed}
    end
  end

  defp owns_run(thread, approval, run) do
    if run.thread_id == thread.id and run.approval_id == approval.id and run.kind == "ship" and
         Threads.owns_run?(run.id, run.attempt),
       do: :ok,
       else: {:error, :stale_run}
  end

  defp approved(thread, approval, reconcile \\ false) do
    # Only an Ecto-loaded approval is accepted, never an HTTP/model-supplied map.
    # Reloading prevents a revoked approval or edited JSON payload being used.
    if is_struct(approval) and Map.has_key?(approval, :__meta__) do
      bound = Repo.reload(approval) == approval and approval_binding?(thread, approval, reconcile)

      if bound and approval_valid?(approval, reconcile) do
        :ok
      else
        {:error, :shipping_approval_invalid}
      end
    else
      {:error, :shipping_approval_invalid}
    end
  end

  defp approval_binding?(thread, approval, reconcile) do
    binding = %{
      thread_id: thread.id,
      account_id: thread.account_id,
      repository: thread.repository,
      mode: thread.ship_mode,
      target_branch: target(thread),
      approved_by_id: thread.owner_id
    }

    Map.take(approval, Map.keys(binding)) == binding and
      (reconcile or approval.sandbox_id == thread.sandbox_id) and
      (approval.base_sha == thread.base_sha or (reconcile and approval.head_sha == thread.base_sha))
  end

  defp approval_valid?(approval, reconcile) do
    (approval.status in [:approved, :executing] or
       (reconcile and approval.status in [:failed, :succeeded, :outcome_unknown])) and
      not is_nil(approval.approved_at) and Workspace.sha?(approval.head_sha) and
      match?({:ok, _}, Ecto.UUID.cast(approval.request_id))
  end

  defp ready(thread) do
    if thread.status == :active and thread.workspace_ready and Workspace.sha?(thread.base_sha) and
         thread.ship_mode in [:direct, :branch], do: :ok, else: {:error, :workspace_unavailable}
  end

  defp idle_sandbox(thread, prefix) do
    case Sandboxes.get_sandbox_by_id(thread.sandbox_id) do
      %Sandbox{account_id: account_id, residency_work_id: residency} = sandbox when account_id == thread.account_id ->
        if is_nil(residency) or String.starts_with?(residency, prefix),
          do: {:ok, sandbox},
          else: {:error, :workspace_busy}

      _ ->
        {:error, :workspace_busy}
    end
  end

  defp with_residency(thread, request_id, fun) do
    prefix = "threads-ship:#{request_id}:"
    # Every invocation gets its own fence, even when recovering the SAME Ship.
    # A delayed old release must not clear the replacement invocation's pin.
    work_id = prefix <> Ecto.UUID.generate()

    with {:ok, sandbox} <- idle_sandbox(thread, prefix),
         {:ok, sandbox} <- Sandboxes.prepare_residency(sandbox, work_id) do
      try do
        fun.(sandbox)
      after
        Workspace.release(%{sandbox: sandbox, residency: work_id})
      end
    else
      _ -> {:error, :workspace_busy}
    end
  end

  defp snapshot(sandbox, thread) do
    case Sandboxes.exec(sandbox, ["python3", "-c", @snapshot, thread.base_sha, thread.id],
           cwd: "/workspace",
           env: %{},
           timeout_ms: 90_000
         ) do
      {:ok, %{exit_code: 0, stdout: output}} ->
        head = String.trim(output)
        if Workspace.sha?(head), do: {:ok, head}, else: {:error, :shipping_snapshot_failed}

      _ ->
        {:error, :shipping_snapshot_failed}
    end
  end

  defp target(%{ship_mode: :direct} = thread), do: thread.base_branch
  defp target(thread), do: thread.branch

  defp success(approval),
    do:
      {:ok,
       %{
         request_id: approval.request_id,
         head_sha: approval.head_sha,
         target_branch: approval.target_branch,
         actor: "GitHub App installation"
       }}
end
