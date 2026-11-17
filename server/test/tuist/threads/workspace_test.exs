defmodule Tuist.Threads.WorkspaceTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  import TuistTestSupport.Fixtures.AccountsFixtures
  import TuistTestSupport.Fixtures.VCSFixtures

  alias Tuist.Agents.Lease
  alias Tuist.GitHub.App
  alias Tuist.GitHub.Client
  alias Tuist.Sandboxes
  alias Tuist.Sandboxes.ProviderEnvironment
  alias Tuist.Sandboxes.Sandbox
  alias Tuist.Threads.Checkout
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
    # The run's host holds the thread's session lease at the run's attempt.
    Lease.want(id, "thread")
    [%{epoch: 1}] = Lease.claim("test-host", 1)

    stub(Client, :list_installation_repositories, fn _, _ ->
      {:ok, %{meta: %{next_url: nil}, repositories: [%{full_name: "Tuist/Example", default_branch: "main"}]}}
    end)

    stub(App, :create_scoped_installation_token, fn _, ["Example"], %{"contents" => "read"} ->
      {:ok, %{token: "ephemeral-read-token"}}
    end)

    # The owner's own GitHub access (`Repository.authorize/4`).
    oauth2_identity_fixture(user: user, provider: :github, id_in_provider: "42")
    stub(Client, :get_user_by_id, fn %{id: "42"} -> {:ok, %Tuist.VCS.User{username: "owner"}} end)

    stub(Client, :get_repository_permission, fn %{username: "owner", repository_full_handle: "Tuist/Example"} ->
      {:ok, "write"}
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

  test "the owner's own GitHub permission decides what the installation may reach for them", c do
    assert {:ok, %{name: "Tuist/Example"}} = Repository.authorize(c.user.account, c.user, "tuist/example", :write)

    stub(Client, :get_repository_permission, fn _ -> {:ok, "read"} end)
    assert {:ok, %{name: "Tuist/Example"}} = Repository.authorize(c.user.account, c.user, "Tuist/Example")
    assert {:error, :repository_access_denied} = Repository.authorize(c.user.account, c.user, "Tuist/Example", :write)

    stub(Client, :get_repository_permission, fn _ -> {:ok, "none"} end)
    assert {:error, :repository_access_denied} = Repository.authorize(c.user.account, c.user, "Tuist/Example")

    # A GitHub user that no longer exists has no access; a lookup that could
    # not be made is not a denial, and nothing is allowed either way.
    stub(Client, :get_repository_permission, fn _ -> {:error, :not_found} end)
    assert {:error, :repository_access_denied} = Repository.authorize(c.user.account, c.user, "Tuist/Example")
    stub(Client, :get_repository_permission, fn _ -> {:error, :unavailable} end)
    assert {:error, :repository_access_unavailable} = Repository.authorize(c.user.account, c.user, "Tuist/Example")

    # A GitHub user who deleted their account reads nothing.
    stub(Client, :get_user_by_id, fn _ -> {:error, "Unexpected status code: 404. Body: {}"} end)
    assert {:error, :repository_access_denied} = Repository.authorize(c.user.account, c.user, "Tuist/Example")

    member = user_fixture()
    assert {:error, :github_identity_missing} = Repository.authorize(c.user.account, member, "Tuist/Example")
  end

  test "an owner who lost access to the repository gets no checkout", c do
    stub(Client, :get_repository_permission, fn _ -> {:ok, "none"} end)
    reject(Sandboxes, :create_sandbox, 2)
    reject(Sandboxes, :exec, 3)
    assert {:error, :repository_access_denied} = Workspace.prepare(c.thread, c.run)
  end

  test "binding is persisted before bootstrap and a failed unpack retries the same sandbox", c do
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

    stub(Repository, :branch_head, fn _account, "Tuist/Example", "main" -> {:ok, @base} end)

    # The server fetches the commit GitHub reported; the guest only gets a URL.
    stub(Checkout, :stage, fn account, sandbox, "Tuist/Example", @base, _opts ->
      assert account.id == c.user.account.id
      assert Repo.reload!(c.thread).sandbox_id == sandbox.id
      {:ok, "https://storage.example.com/checkout?signature=s"}
    end)

    log = start_supervised!({Agent, fn -> [] end})

    stub(Sandboxes, :exec, fn sandbox, argv, opts ->
      Agent.update(log, &[{argv, opts[:env]} | &1])
      assert Repo.reload!(c.thread).sandbox_id == sandbox.id
      refute Repo.reload!(c.thread).workspace_ready
      if hd(argv) == "/bin/bash", do: result("", 22), else: result("")
    end)

    assert {:error, :workspace_clone_failed} = Workspace.prepare(c.thread, c.run)
    thread = Repo.reload!(c.thread)
    assert thread.sandbox_id
    refute thread.workspace_ready
    assert Repo.get!(Sandbox, thread.sandbox_id).residency_work_id == nil

    # The unpack received the archive URL, the base and the branch, and no
    # repository credential; its fresh staging directory is removed, and
    # /workspace/repository is only replaced by a verified checkout.
    calls = Agent.get(log, &Enum.reverse/1)
    {_, env} = Enum.find(calls, fn {argv, _} -> hd(argv) == "/bin/bash" end)
    assert env["CHECKOUT_URL"] == "https://storage.example.com/checkout?signature=s"
    assert env["BASE"] == @base
    assert env["BRANCH"] == "threads/#{c.thread.id}"
    assert env["STAGING"] =~ ~r{\A\.tuist-checkout-}
    refute Enum.any?(Map.values(env), &String.contains?(&1, "ephemeral-read-token"))
    refute Enum.any?(Map.keys(env), &String.starts_with?(&1, "GIT_CONFIG"))

    assert Enum.any?(calls, fn {argv, _} ->
             argv == ["rm", "-rf", "--", "/workspace/" <> env["STAGING"], "/workspace/#{env["STAGING"]}.tar"]
           end)

    stub(Sandboxes, :exec, fn _, _, _ -> result("") end)

    assert {:ok, context} = Workspace.prepare(thread, c.run)
    assert context.sandbox.id == thread.sandbox_id
    assert context.thread.base_sha == @base
    assert context.thread.workspace_ready
    assert context.residency == "threads:#{c.run.id}:1"
    assert Repo.aggregate(Sandbox, :count) == 1
    assert :ok = Workspace.release(context)
    assert Repo.get!(Sandbox, thread.sandbox_id).residency_work_id == nil
  end

  test "a checkout the server could not stage never reaches the guest", c do
    environment =
      Repo.insert!(%ProviderEnvironment{account_id: c.user.account.id, external_key: "threads/#{c.thread.id}"})

    sandbox =
      Repo.insert!(%Sandbox{account_id: c.user.account.id, provider_environment_id: environment.id, state: :running})

    thread = Repo.update!(Ecto.Changeset.change(c.thread, sandbox_id: sandbox.id))
    stub(Repository, :branch_head, fn _, _, _ -> {:ok, @base} end)
    stub(Checkout, :stage, fn _, _, _, _, _ -> {:error, :checkout_too_large} end)

    stub(Sandboxes, :exec, fn _, argv, _ ->
      assert hd(argv) == "rm", "unexpected guest operation: #{inspect(argv)}"
      result("")
    end)

    # An archive too large to check out ever would fail every later run: the
    # thread gives the repository up instead.
    assert {:error, :repository_too_large} = Workspace.prepare(thread, c.run)
    thread = Repo.reload!(thread)
    refute thread.workspace_ready
    assert {thread.repository, thread.base_branch, thread.branch} == {nil, nil, nil}

    # Any other failure leaves it bound for the next run to retry.
    thread = Repo.update!(Ecto.Changeset.change(thread, repository: "Tuist/Example", base_branch: "main", branch: "b"))
    stub(Checkout, :stage, fn _, _, _, _, _ -> {:error, :checkout_unavailable} end)
    assert {:error, :workspace_clone_failed} = Workspace.prepare(thread, c.run)
    assert Repo.reload!(thread).repository == "Tuist/Example"
  end

  test "a repository bound mid-run is checked out in that run's sandbox", c do
    environment =
      Repo.insert!(%ProviderEnvironment{account_id: c.user.account.id, external_key: "threads/#{c.thread.id}"})

    sandbox =
      Repo.insert!(%Sandbox{account_id: c.user.account.id, provider_environment_id: environment.id, state: :running})

    thread =
      Repo.update!(
        Ecto.Changeset.change(c.thread, sandbox_id: sandbox.id, repository: nil, base_branch: nil, branch: nil)
      )

    reject(Sandboxes, :create_sandbox, 2)
    assert {:ok, context} = Workspace.prepare(thread, c.run)
    refute context.thread.workspace_ready

    # The agent's request_repository binds it (`Threads.request_repository/2`).
    Repo.update!(
      Ecto.Changeset.change(thread, repository: "Tuist/Example", base_branch: "main", branch: "threads/#{thread.id}")
    )

    stub(Repository, :branch_head, fn _, "Tuist/Example", "main" -> {:ok, @base} end)

    stub(Checkout, :stage, fn _, %{id: id}, "Tuist/Example", @base, opts when id == sandbox.id ->
      # A mid-run checkout must fit in the tool call's 300 s.
      assert opts[:fetch_ms] + opts[:archive_ms] * 3 < 300_000
      {:ok, "https://archive"}
    end)

    stub(Sandboxes, :exec, fn %{id: id}, ["/bin/bash" | _], opts when id == sandbox.id ->
      assert opts[:env]["BRANCH"] == "threads/#{thread.id}"
      result("")
    end)

    assert {:ok, attached} = Workspace.attach(context)
    assert attached.workspace_ready
    assert attached.base_sha == @base
    assert Repo.reload!(sandbox).residency_work_id == context.residency

    # A run that no longer owns the thread attaches nothing.
    Repo.update!(Ecto.Changeset.change(c.run, status: "succeeded"))
    reject(Sandboxes, :exec, 3)
    assert {:error, :stale_run} = Workspace.attach(context)
  end

  test "the guest's unpack script installs the staged checkout and only a verified one", c do
    # The real script, run by a local bash in place of the guest, on an archive
    # built as `Checkout.stage/5` builds it.
    root = Briefly.create!(directory: true)
    origin = Path.join(root, "origin")
    workspace = Path.join(root, "workspace")
    File.mkdir_p!(origin)
    File.mkdir_p!(Path.join(workspace, "repository"))
    File.write!(Path.join([workspace, "repository", "old"]), "previous checkout")
    git!(origin, ["init", "--quiet", "--initial-branch=main"])
    File.write!(Path.join(origin, "README.md"), "hello\n")
    git!(origin, ["add", "."])
    git!(origin, ["commit", "--quiet", "-m", "First"])
    base = String.trim(git!(origin, ["rev-parse", "HEAD"]))
    store = Path.join(root, "store.git")
    git!(root, ["clone", "--quiet", "--bare", "--depth", "1", "file://" <> origin, store])
    archive = Path.join(root, "checkout.tar")
    {_, 0} = System.cmd("tar", ["-cf", archive, "-C", store, "."])

    environment =
      Repo.insert!(%ProviderEnvironment{account_id: c.user.account.id, external_key: "threads/#{c.thread.id}"})

    sandbox =
      Repo.insert!(%Sandbox{account_id: c.user.account.id, provider_environment_id: environment.id, state: :running})

    thread = Repo.update!(Ecto.Changeset.change(c.thread, sandbox_id: sandbox.id))
    stub(Repository, :branch_head, fn _, _, _ -> {:ok, base} end)
    stub(Checkout, :stage, fn _, _, _, _, _ -> {:ok, "file://" <> archive} end)

    stub(Sandboxes, :exec, fn
      _, ["/bin/bash", "-c", script], opts ->
        env = Map.put(opts[:env], "WORKSPACE", workspace)
        {output, code} = System.cmd("/bin/bash", ["-c", script], env: Map.to_list(env), stderr_to_stdout: true)
        {:ok, %{stdout: output, stderr: "", exit_code: code}}

      _, ["rm" | _], _ ->
        result("")
    end)

    assert {:ok, context} = Workspace.prepare(thread, c.run)
    assert context.thread.workspace_ready
    checkout = Path.join(workspace, "repository")
    assert File.read!(Path.join(checkout, "README.md")) == "hello\n"
    assert String.trim(git!(checkout, ["symbolic-ref", "--short", "HEAD"])) == thread.branch
    assert String.trim(git!(checkout, ["rev-parse", "HEAD"])) == base
    # The previous checkout was moved aside, not deleted or merged into.
    refute File.exists?(Path.join(checkout, "old"))
    assert [previous] = Path.wildcard(Path.join(workspace, "repository.previous-*"))
    assert File.read!(Path.join(previous, "old")) == "previous checkout"
    Workspace.release(context)

    # A base the archive does not hold leaves the installed checkout alone.
    thread = Repo.update!(Ecto.Changeset.change(Repo.reload!(thread), workspace_ready: false))
    stub(Repository, :branch_head, fn _, _, _ -> {:ok, String.duplicate("b", 40)} end)
    assert {:error, :workspace_clone_failed} = Workspace.prepare(thread, c.run)
    assert String.trim(git!(checkout, ["rev-parse", "HEAD"])) == base
    assert length(Path.wildcard(Path.join(workspace, "repository.previous-*"))) == 1
  end

  test "a sandbox that failed to boot is replaced while the thread holds no checkout", c do
    environment =
      Repo.insert!(%ProviderEnvironment{account_id: c.user.account.id, external_key: "threads/#{c.thread.id}"})

    errored =
      Repo.insert!(%Sandbox{account_id: c.user.account.id, provider_environment_id: environment.id, state: :error})

    thread = Repo.update!(Ecto.Changeset.change(c.thread, repository: nil, base_branch: nil, branch: nil))

    expect(Sandboxes, :delete, fn sandbox ->
      assert sandbox.id == errored.id
      {:ok, Repo.delete!(sandbox)}
    end)

    expect(Sandboxes, :create_sandbox, fn account, %{provider_environment_id: id} ->
      assert id == environment.id
      {:ok, Repo.insert!(%Sandbox{account_id: account.id, provider_environment_id: id, state: :running})}
    end)

    stub(Sandboxes, :exec, fn _, argv, _ -> flunk("unexpected exec: #{inspect(argv)}") end)

    assert {:ok, context} = Workspace.prepare(thread, c.run)
    refute context.sandbox.id == errored.id
    assert Repo.reload!(thread).sandbox_id == context.sandbox.id
  end

  test "a placed sandbox in error keeps its disks rather than being replaced", c do
    environment =
      Repo.insert!(%ProviderEnvironment{account_id: c.user.account.id, external_key: "threads/#{c.thread.id}"})

    errored =
      Repo.insert!(%Sandbox{
        account_id: c.user.account.id,
        provider_environment_id: environment.id,
        state: :error,
        node_name: nil,
        last_active_at: DateTime.utc_now(:second)
      })

    thread = Repo.update!(Ecto.Changeset.change(c.thread, repository: nil, base_branch: nil, branch: nil))
    reject(Sandboxes, :delete, 1)
    reject(Sandboxes, :create_sandbox, 2)
    stub(Sandboxes, :prepare_residency, fn _, _ -> {:error, {:invalid_state, :error}} end)

    assert {:error, {:invalid_state, :error}} = Workspace.prepare(thread, c.run)
    assert Repo.reload!(errored).state == :error
    assert Repo.reload!(thread).sandbox_id == errored.id
  end

  test "a ready checkout keeps its persisted branch after the Thread rename", c do
    sandbox = Repo.insert!(%Sandbox{account_id: c.user.account.id, state: :running})

    thread =
      Repo.update!(
        Ecto.Changeset.change(c.thread,
          sandbox_id: sandbox.id,
          workspace_ready: true,
          base_sha: @base,
          branch: "threads/#{c.thread.id}"
        )
      )

    reject(Sandboxes, :create_sandbox, 2)

    stub(Sandboxes, :exec, fn _, argv, _ ->
      cond do
        "--show-toplevel" in argv -> result("/workspace/repository")
        "get-url" in argv -> result("https://github.com/Tuist/Example.git")
        "symbolic-ref" in argv -> result(thread.branch)
        "cat-file" in argv -> result("")
        true -> flunk("unexpected checkout operation: #{inspect(argv)}")
      end
    end)

    assert {:ok, context} = Workspace.prepare(thread, c.run)
    assert context.thread.branch == thread.branch
    assert :ok = Workspace.release(context)
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
    assert {:error, :workspace_missing} = Workspace.prepare(thread, c.run)
  end

  test "old release cannot clear the replacement attempt's residency", c do
    sandbox = Repo.insert!(%Sandbox{account_id: c.user.account.id, state: :running, residency_work_id: "replacement"})
    reject(Sandboxes, :end_residency, 1)
    assert :ok = Workspace.release(%{sandbox: sandbox, residency: "old-attempt"})
    assert Repo.reload!(sandbox).residency_work_id == "replacement"
  end

  defp git!(cd, args) do
    env = [
      {"GIT_CONFIG_NOSYSTEM", "1"},
      {"GIT_CONFIG_GLOBAL", "/dev/null"},
      {"GIT_AUTHOR_NAME", "Test"},
      {"GIT_AUTHOR_EMAIL", "test@tuist.dev"},
      {"GIT_COMMITTER_NAME", "Test"},
      {"GIT_COMMITTER_EMAIL", "test@tuist.dev"}
    ]

    {output, 0} = System.cmd("git", args, cd: cd, env: env, stderr_to_stdout: true)
    output
  end

  defp result(output, code \\ 0), do: {:ok, %{stdout: output, stderr: "", exit_code: code}}
end
