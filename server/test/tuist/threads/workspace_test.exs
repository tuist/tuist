defmodule Tuist.Threads.WorkspaceTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  import TuistTestSupport.Fixtures.AccountsFixtures
  import TuistTestSupport.Fixtures.VCSFixtures

  alias Tuist.GitHub.App
  alias Tuist.GitHub.Client
  alias Tuist.Sandboxes
  alias Tuist.Sandboxes.ProviderEnvironment
  alias Tuist.Sandboxes.Sandbox
  alias Tuist.Threads
  alias Tuist.Threads.Repository
  alias Tuist.Threads.Run
  alias Tuist.Threads.Thread
  alias Tuist.Threads.Workspace

  @base String.duplicate("a", 40)

  setup do
    user = user_fixture()
    github_app_installation_fixture(account: user)
    id = Ecto.UUID.generate()

    thread =
      Repo.insert!(%Thread{
        id: id,
        account_id: user.account.id,
        owner_id: user.id,
        request_id: Ecto.UUID.generate(),
        request_hash: :crypto.hash(:sha256, id),
        title: "Fix",
        goal: "Fix",
        provider: "chatgpt",
        model: "selected-model",
        repository: "Tuist/Example",
        base_branch: "main",
        branch: "threads/#{id}"
      })

    run = Repo.insert!(%Run{thread_id: id, status: "running", attempt: 1, heartbeat_at: DateTime.utc_now(:second)})

    stub(Client, :list_installation_repositories, fn _, _ ->
      {:ok, %{meta: %{next_url: nil}, repositories: [%{full_name: "Tuist/Example", default_branch: "main"}]}}
    end)

    stub(App, :create_scoped_installation_token, fn _, ["Example"], %{"contents" => "read"} ->
      {:ok, %{token: "ephemeral-read-token"}}
    end)

    stub(Sandboxes, :prepare_residency, fn sandbox, work_id ->
      {:ok, Repo.update!(Ecto.Changeset.change(sandbox, residency_work_id: work_id))}
    end)

    stub(Sandboxes, :end_residency, fn sandbox ->
      {:ok, Repo.update!(Ecto.Changeset.change(sandbox, residency_work_id: nil))}
    end)

    %{thread: thread, run: run, user: user}
  end

  test "fresh installation catalog canonicalizes names and fails closed on revocation", c do
    assert {:ok, %{name: "Tuist/Example", default_branch: "main"}} = Repository.authorize(c.user.account, "tuist/example")
    stub(Client, :list_installation_repositories, fn _, _ -> {:ok, %{meta: %{next_url: nil}, repositories: []}} end)
    assert {:error, :repository_not_authorized} = Repository.authorize(c.user.account, "Tuist/Example")
    assert {:error, :repository_not_authorized} = Repository.authorize(c.user.account, "https://github.com/Tuist/Example")
  end

  test "binding is persisted before bootstrap and failed fetch retries the same sandbox", c do
    expect(Sandboxes, :create_sandbox, fn account, attrs ->
      assert account.id == c.user.account.id
      assert Map.keys(attrs) == [:provider_environment_id]
      assert Repo.get!(ProviderEnvironment, attrs.provider_environment_id).external_key == "threads/#{c.thread.id}"

      {:ok,
       Repo.insert!(%Sandbox{
         account_id: account.id,
         provider_environment_id: attrs.provider_environment_id,
         state: :running
       })}
    end)

    stub(Sandboxes, :exec, fn sandbox, argv, opts ->
      assert Repo.reload!(c.thread).sandbox_id == sandbox.id
      refute Repo.reload!(c.thread).workspace_ready
      assert opts[:cwd] in ["/workspace", "/workspace/repository"]

      cond do
        hd(argv) == "python3" ->
          result("empty\n")

        "fetch" in argv ->
          assert opts[:env]["GIT_CONFIG_VALUE_0"] =~ "AUTHORIZATION: basic "
          refute Enum.any?(argv, &String.contains?(&1, "ephemeral-read-token"))
          {:error, :timeout}

        "get-url" in argv ->
          result("https://github.com/Tuist/Example.git")

        "rev-parse" in argv ->
          result("", 1)

        true ->
          result("")
      end
    end)

    assert {:error, :workspace_clone_failed} = Workspace.prepare(c.thread, c.run)
    thread = Repo.reload!(c.thread)
    assert thread.sandbox_id
    refute thread.workspace_ready
    assert Repo.get!(Sandbox, thread.sandbox_id).residency_work_id == nil

    stub(Sandboxes, :exec, fn _, argv, _ ->
      cond do
        hd(argv) == "python3" -> result("initialized\n")
        "get-url" in argv -> result("https://github.com/Tuist/Example.git")
        "refs/tuist/base^{commit}" in argv -> result("", 1)
        "rev-parse" in argv -> result(@base)
        "show-ref" in argv -> result("", 1)
        true -> result("")
      end
    end)

    assert {:ok, context} = Workspace.prepare(thread, c.run)
    assert context.sandbox.id == thread.sandbox_id
    assert context.thread.base_sha == @base
    assert context.thread.workspace_ready
    assert context.residency == "threads:#{c.run.id}:1"
    assert Repo.aggregate(Sandbox, :count) == 1
    assert :ok = Workspace.release(context)
    assert Repo.get!(Sandbox, thread.sandbox_id).residency_work_id == nil
  end

  test "a missing ready checkout fails visibly without cloning or creating a replacement", c do
    sandbox = Repo.insert!(%Sandbox{account_id: c.user.account.id, state: :running})
    thread = Repo.update!(Ecto.Changeset.change(c.thread, sandbox_id: sandbox.id, workspace_ready: true, base_sha: @base))
    reject(Sandboxes, :create_sandbox, 2)

    expect(Sandboxes, :exec, fn _, argv, _ ->
      assert "--show-toplevel" in argv
      result("missing", 1)
    end)

    assert {:error, :workspace_checkout_missing} = Workspace.prepare(thread, c.run)
    assert Repo.reload!(thread).sandbox_id == sandbox.id

    # The same FK nilification used by sandbox retention must not provision a
    # replacement that appears to contain the user's lost, unpushed changes.
    thread = Repo.update!(Ecto.Changeset.change(thread, sandbox_id: nil))
    assert {:error, :workspace_unavailable} = Workspace.prepare(thread, c.run)
  end

  test "old release cannot clear the replacement attempt's residency", c do
    sandbox = Repo.insert!(%Sandbox{account_id: c.user.account.id, state: :running, residency_work_id: "replacement"})
    reject(Sandboxes, :end_residency, 1)
    assert :ok = Workspace.release(%{sandbox: sandbox, residency: "old-attempt"})
    assert Repo.reload!(sandbox).residency_work_id == "replacement"
  end

  test "tool paths, payloads and output are bounded and unsupported tools cannot Ship", c do
    context = %{thread: c.thread, sandbox: %Sandbox{}, run_id: c.run.id, attempt: c.run.attempt}
    reject(Sandboxes, :exec, 3)

    for path <- ["/etc/passwd", "../secret", ".git/config", "a/../secret", "a//b"] do
      assert {:error, :invalid_arguments} = Workspace.call(context, "read", %{"path" => path})
    end

    assert {:error, :invalid_arguments} = Workspace.call(context, "bash", %{"command" => String.duplicate("x", 8001)})
    assert {:error, :invalid_arguments} = Workspace.call(context, "ship", %{})
  end

  test "file operations reject symlink parents and final symlinks without truncation", c do
    {:ok, directory} = Briefly.create(directory: true)
    File.mkdir_p!(Path.join(directory, "repository"))
    File.write!(Path.join(directory, "secret"), "preserve")
    File.ln_s!(directory, Path.join(directory, "repository/link"))
    File.ln_s!(Path.join(directory, "secret"), Path.join(directory, "repository/file"))
    sandbox = Repo.insert!(%Sandbox{account_id: c.thread.account_id, state: :running, residency_work_id: "test-files"})
    context = %{thread: c.thread, sandbox: sandbox, residency: "test-files", run_id: c.run.id, attempt: c.run.attempt}

    stub(Sandboxes, :exec, fn _, ["python3", "-c", script | args], opts ->
      assert opts[:env] == %{}

      {output, code} =
        System.cmd("python3", ["-c", String.replace(script, "/workspace", directory) | args], stderr_to_stdout: true)

      {:ok, %{stdout: output, stderr: "", exit_code: code}}
    end)

    for path <- ["link/secret", "file"] do
      assert {:ok, output} = Workspace.call(context, "write", %{"path" => path, "content" => "overwrite"})
      refute output =~ "exit_code=0"
    end

    assert File.read!(Path.join(directory, "secret")) == "preserve"
    assert {:ok, _} = Workspace.call(context, "write", %{"path" => "normal", "content" => "old"})
    assert {:ok, _} = Workspace.call(context, "edit", %{"path" => "normal", "old_text" => "old", "new_text" => "new"})
    assert File.read!(Path.join(directory, "repository/normal")) == "new"
  end

  test "shell receives only a bounded command with fixed cwd and no credentials", c do
    sandbox = Repo.insert!(%Sandbox{account_id: c.thread.account_id, state: :running, residency_work_id: "test-shell"})
    context = %{thread: c.thread, sandbox: sandbox, residency: "test-shell", run_id: c.run.id, attempt: c.run.attempt}

    expect(Sandboxes, :exec, fn _, argv, opts ->
      assert argv == ["/bin/bash", "--noprofile", "--norc", "-c", "printf hello"]
      assert opts == [cwd: "/workspace/repository", env: %{}, timeout_ms: 60_000]
      result(String.duplicate("x", 100_000))
    end)

    assert {:ok, output} =
             Threads.call_tool(c.run, Map.put(context, :invocation_id, Ecto.UUID.generate()), "bash", %{
               "command" => "printf hello"
             })

    assert byte_size(output) <= 65_536
    assert output =~ "[Output truncated]"
  end

  test "stale attempts cannot invoke shell", c do
    reject(Sandboxes, :exec, 3)
    context = %{thread: c.thread, sandbox: %Sandbox{}, run_id: c.run.id, attempt: 0}
    assert {:error, :stale_run} = Workspace.call(context, "bash", %{"command" => "touch marker"})
  end

  defp result(output, code \\ 0), do: {:ok, %{stdout: output, stderr: "", exit_code: code}}
end
