defmodule Tuist.Threads.ShippingTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  import TuistTestSupport.Fixtures.AccountsFixtures
  import TuistTestSupport.Fixtures.VCSFixtures

  alias Tuist.GitHub.App
  alias Tuist.GitHub.Client
  alias Tuist.Sandboxes
  alias Tuist.Sandboxes.Sandbox
  alias Tuist.Threads.Approval
  alias Tuist.Threads.Repository
  alias Tuist.Threads.Shipping
  alias Tuist.Threads.Thread

  @base String.duplicate("a", 40)
  @head String.duplicate("b", 40)
  @tree String.duplicate("c", 40)

  setup do
    user = user_fixture()
    github_app_installation_fixture(account: user)
    sandbox = Repo.insert!(%Sandbox{account_id: user.account.id, state: :running})
    id = Ecto.UUID.generate()

    thread =
      Repo.insert!(%Thread{
        id: id,
        account_id: user.account.id,
        owner_id: user.id,
        request_id: Ecto.UUID.generate(),
        request_hash: :crypto.hash(:sha256, id),
        goal: "Fix",
        title: "Fix",
        provider: "chatgpt",
        model: "selected-model",
        repository: "Tuist/Example",
        base_branch: "main",
        branch: "threads/#{id}",
        base_sha: @base,
        sandbox_id: sandbox.id,
        workspace_ready: true,
        ship_mode: :direct
      })

    approval =
      Repo.insert!(%Approval{
        request_id: Ecto.UUID.generate(),
        thread_id: id,
        account_id: user.account.id,
        repository: thread.repository,
        sandbox_id: sandbox.id,
        head_sha: @head,
        base_sha: @base,
        diff: "reviewed diff",
        target_branch: "main",
        mode: :direct,
        approved_by_id: user.id,
        approved_at: DateTime.utc_now(:second),
        status: :approved
      })

    blob = Base.encode16(:crypto.hash(:sha, "blob 4\0data"), case: :lower)

    objects = %{
      "tree_sha" => @tree,
      "entries" => [
        %{"path" => "file", "mode" => "100644", "type" => "blob", "sha" => blob, "content" => Base.encode64("data")}
      ]
    }

    {:ok, remote} = Agent.start_link(fn -> @base end)

    stub(Client, :list_installation_repositories, fn _, _ ->
      {:ok, %{meta: %{next_url: nil}, repositories: [%{full_name: "Tuist/Example", default_branch: "main"}]}}
    end)

    stub(App, :create_scoped_installation_token, fn _, ["Example"], %{"contents" => permission} ->
      {:ok, %{token: "server-only-#{permission}-token"}}
    end)

    stub(Sandboxes, :prepare_residency, fn sandbox, work_id ->
      {:ok, Repo.update!(Ecto.Changeset.change(sandbox, residency_work_id: work_id))}
    end)

    stub(Sandboxes, :end_residency, fn sandbox ->
      {:ok, Repo.update!(Ecto.Changeset.change(sandbox, residency_work_id: nil))}
    end)

    stub(Sandboxes, :exec, fn _, ["python3", "-c", script | _], opts ->
      assert opts[:env] == %{}
      refute script =~ "server-only"
      if script =~ "json.dumps", do: result(JSON.encode!(objects)), else: result(@head)
    end)

    stub(Req, :get, fn opts ->
      assert opts[:url] =~ "/rules/branches/"
      {:ok, %{status: 200, body: []}}
    end)

    stub(Req, :post, fn opts ->
      assert opts[:url] == "https://api.github.com/graphql"

      case opts[:json] do
        %{variables: %{input: input}} ->
          [update] = input.refUpdates
          assert update.force == false
          assert update.beforeOid == (Agent.get(remote, & &1) || String.duplicate("0", 40))
          assert update.afterOid == @head
          Agent.update(remote, fn _ -> @head end)
          {:ok, %{status: 200, body: %{"data" => %{"updateRefs" => %{}}}}}

        _ ->
          policy([])
      end
    end)

    stub(Req, :request, fn opts ->
      {"authorization", header} = List.keyfind(opts[:headers], "authorization", 0)
      assert header in ["Bearer server-only-write-token", "Bearer server-only-read-token"]
      assert opts[:retry] == false
      assert opts[:redirect] == false
      path = URI.parse(opts[:url]).path

      body =
        case {opts[:method], path} do
          {:get, "/repos/Tuist/Example/git/ref/heads/" <> _} ->
            %{"object" => %{"sha" => Agent.get(remote, & &1)}}

          {:get, "/repos/Tuist/Example/git/commits/" <> _} ->
            %{"tree" => %{"sha" => @tree}}

          {:get, "/repos/Tuist/Example"} ->
            %{"node_id" => "repository-node"}

          {:post, "/repos/Tuist/Example/git/blobs"} ->
            %{"sha" => blob}

          {:post, "/repos/Tuist/Example/git/trees"} ->
            %{"sha" => @tree}

          {:post, "/repos/Tuist/Example/git/commits"} ->
            assert opts[:json].parents == [@base]
            assert opts[:json].message == "Tuist Threads #{id}\n"
            %{"sha" => @head}

          unexpected ->
            flunk("Unexpected broker request: #{inspect(unexpected)}")
        end

      status =
        cond do
          String.contains?(path, "/git/ref/heads/") and is_nil(Agent.get(remote, & &1)) -> 404
          opts[:method] == :post -> 201
          true -> 200
        end

      {:ok, %{status: status, body: body}}
    end)

    %{user: user, thread: thread, approval: approval, sandbox: sandbox, objects: objects, remote: remote}
  end

  test "Ship verifies immutable objects and atomically compares the target with no write token in the guest", c do
    assert {:ok, %{head_sha: @head, actor: "GitHub App installation"}} = Shipping.execute(c.thread, c.approval)
    assert Agent.get(c.remote, & &1) == @head
    assert Repo.reload!(c.sandbox).residency_work_id == nil
  end

  test "retry reconciles a remotely completed Ship without snapshotting or writing again", c do
    Agent.update(c.remote, fn _ -> @head end)
    reject(Sandboxes, :exec, 3)
    assert {:ok, %{head_sha: @head}} = Shipping.execute(c.thread, c.approval)
  end

  test "branch mode creates only the thread branch with an atomic absent-ref precondition", c do
    thread = Repo.update!(Ecto.Changeset.change(c.thread, ship_mode: :branch))
    approval = Repo.update!(Ecto.Changeset.change(c.approval, mode: :branch, target_branch: thread.branch))
    Agent.update(c.remote, fn _ -> nil end)
    assert {:ok, %{target_branch: target}} = Shipping.execute(thread, approval)
    assert target == thread.branch
  end

  test "archived uncertain shipments reconcile positively without a VM or any write", c do
    thread = Repo.update!(Ecto.Changeset.change(c.thread, status: :archived, workspace_ready: false, sandbox_id: nil))
    reject(Sandboxes, :prepare_residency, 2)
    reject(Sandboxes, :exec, 3)
    reject(Req, :post, 1)
    assert {:error, :shipping_uncertain} = Shipping.reconcile(thread, c.approval)
    Agent.update(c.remote, fn _ -> @head end)
    assert {:ok, %{head_sha: @head}} = Shipping.reconcile(thread, c.approval)
  end

  test "a changed target refuses before reading or uploading workspace objects", c do
    Agent.update(c.remote, fn _ -> String.duplicate("d", 40) end)
    reject(Sandboxes, :exec, 3)
    assert {:error, :shipping_base_changed} = Shipping.execute(c.thread, c.approval)
  end

  test "unreviewed workspace edits invalidate approval", c do
    stub(Sandboxes, :exec, fn _, _, opts ->
      assert opts[:env] == %{}
      result(String.duplicate("e", 40))
    end)

    assert {:error, :shipping_review_stale} = Shipping.execute(c.thread, c.approval)
    assert Agent.get(c.remote, & &1) == @base
  end

  test "plain maps and revoked approvals cannot execute", c do
    assert {:error, :shipping_approval_invalid} = Shipping.execute(c.thread, Map.from_struct(c.approval))
    Repo.update!(Ecto.Changeset.change(c.approval, status: :failed))
    assert {:error, :shipping_approval_invalid} = Shipping.execute(c.thread, c.approval)
  end

  test "active run prevents preview, but the same crashed Ship residency can be recovered", c do
    Repo.update!(Ecto.Changeset.change(c.sandbox, residency_work_id: "threads:active:1"))
    assert {:error, :workspace_busy} = Shipping.preview(c.user, c.thread)

    Repo.update!(
      Ecto.Changeset.change(Repo.reload!(c.sandbox),
        residency_work_id: "threads-ship:#{c.approval.request_id}:old-invocation"
      )
    )

    Agent.update(c.remote, fn _ -> @head end)
    assert {:ok, _} = Shipping.execute(c.thread, c.approval)
  end

  test "PR-required rules and classic protections refuse even if the App could bypass them", c do
    stub(Req, :get, fn _ -> {:ok, %{status: 200, body: [%{"type" => "pull_request"}]}} end)
    assert {:error, :pull_request_required} = Shipping.execute(c.thread, c.approval)
    stub(Req, :get, fn _ -> {:ok, %{status: 200, body: []}} end)
    stub(Req, :post, fn _ -> policy([%{"pattern" => "m*"}]) end)
    assert {:error, :protected_branch} = Shipping.execute(c.thread, c.approval)
  end

  test "invalid exported bytes never reach a ref mutation", c do
    objects = put_in(c.objects, ["entries", Access.at(0), "content"], Base.encode64("unreviewed"))
    assert {:error, :shipping_objects_invalid} = Repository.ship(c.user.account, c.approval, fn -> {:ok, objects} end)
    assert Agent.get(c.remote, & &1) == @base
  end

  test "a lost mutation response reconciles success instead of pushing a second time", c do
    stub(Req, :post, fn opts ->
      if opts[:json][:variables][:input] do
        Agent.update(c.remote, fn _ -> @head end)
        {:error, :timeout}
      else
        policy([])
      end
    end)

    assert {:ok, %{head_sha: @head}} = Shipping.execute(c.thread, c.approval)
  end

  test "an unconfirmed mutation stays uncertain even when the destination still has its old head", c do
    for response <- [
          {:error, :timeout},
          {:ok, %{status: 200, body: %{"errors" => [%{"type" => "INTERNAL", "message" => "Operation interrupted"}]}}}
        ] do
      stub(Req, :post, fn opts ->
        if opts[:json][:variables][:input], do: response, else: policy([])
      end)

      assert {:error, :shipping_uncertain} = Shipping.execute(c.thread, c.approval)
    end

    assert Agent.get(c.remote, & &1) == @base
    reject(Req, :post, 1)
    assert {:error, :shipping_uncertain} = Shipping.reconcile(c.thread, c.approval)
  end

  test "preview snapshots tracked and new files without moving HEAD or modifying the real index", c do
    {:ok, directory} = Briefly.create(directory: true)
    root = Path.join(directory, "repository")
    File.mkdir_p!(root)
    git!(root, ["init"])
    root = git!(root, ["rev-parse", "--show-toplevel"])
    directory = Path.dirname(root)
    File.write!(Path.join(root, "tracked"), "before\n")
    File.write!(Path.join(root, "unchanged-asset"), :binary.copy("x", 2 * 1024 * 1024))
    git!(root, ["add", "."])
    git!(root, ["-c", "user.name=Test", "-c", "user.email=test@example.com", "commit", "-m", "base"])
    base = git!(root, ["rev-parse", "HEAD"])
    index = File.read!(Path.join(root, ".git/index"))
    File.write!(Path.join(root, "tracked"), "after\n")
    File.write!(Path.join(root, "new"), "new file\n")
    thread = Repo.update!(Ecto.Changeset.change(c.thread, base_sha: base))

    stub(Sandboxes, :exec, fn _, argv, opts ->
      {output, code} =
        case argv do
          ["python3", "-c", script | args] ->
            assert opts[:env] == %{}
            System.cmd("python3", ["-c", String.replace(script, "/workspace", directory) | args], stderr_to_stdout: true)

          ["git" | args] ->
            refute inspect(opts[:env]) =~ "server-only"
            System.cmd("git", args, cd: root, stderr_to_stdout: true)
        end

      {:ok, %{stdout: output, stderr: "", exit_code: code}}
    end)

    assert {:ok, preview} = Shipping.preview(c.user, thread)
    assert preview.diff =~ "+after"
    assert preview.diff =~ "+new file"
    assert preview.actor =~ "GitHub App"
    assert {:ok, repeat} = Shipping.preview(c.user, thread)
    assert repeat.head_sha == preview.head_sha
    refute preview.diff =~ "unchanged-asset"
    assert git!(root, ["rev-parse", "HEAD"]) == base
    assert File.read!(Path.join(root, ".git/index")) == index
    File.write!(Path.join(root, "unchanged-asset"), :binary.copy("y", 2 * 1024 * 1024))
    assert {:error, :shipping_snapshot_failed} = Shipping.preview(c.user, thread)
  end

  defp policy(patterns),
    do:
      {:ok,
       %{
         status: 200,
         body: %{
           "data" => %{
             "repository" => %{"branchProtectionRules" => %{"totalCount" => length(patterns), "nodes" => patterns}}
           }
         }
       }}

  defp result(output), do: {:ok, %{stdout: output, stderr: "", exit_code: 0}}

  defp git!(root, args) do
    {output, 0} = System.cmd("git", args, cd: root, stderr_to_stdout: true)
    String.trim(output)
  end
end
