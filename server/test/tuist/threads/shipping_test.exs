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
  alias Tuist.Threads.Run
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

    run =
      Repo.insert!(%Run{
        thread_id: thread.id,
        approval_id: approval.id,
        kind: "ship",
        status: "running",
        attempt: 1,
        heartbeat_at: DateTime.utc_now(:second)
      })

    blob = Base.encode16(:crypto.hash(:sha, "blob 4\0data"), case: :lower)

    objects = %{
      "tree_sha" => @tree,
      "entries" => [
        %{"path" => "file", "mode" => "100644", "type" => "blob", "sha" => blob, "content" => Base.encode64("data")}
      ]
    }

    stub(Repository, :review, fn _, _, ^objects -> {:ok, "reviewed diff"} end)

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

    broker = fn opts ->
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
    end

    stub(Req, :request, broker)

    %{
      user: user,
      thread: thread,
      approval: approval,
      run: run,
      sandbox: sandbox,
      objects: objects,
      remote: remote,
      broker: broker
    }
  end

  test "Ship verifies immutable objects and atomically compares the target with no write token in the guest", c do
    assert {:ok, %{head_sha: @head, actor: "GitHub App installation"}} = Shipping.execute(c.thread, c.approval, c.run)
    assert Agent.get(c.remote, & &1) == @head
    assert Repo.reload!(c.sandbox).residency_work_id == nil
  end

  test "retry reconciles a remotely completed Ship without snapshotting or writing again", c do
    Agent.update(c.remote, fn _ -> @head end)
    reject(Sandboxes, :exec, 3)
    assert {:ok, %{head_sha: @head}} = Shipping.execute(c.thread, c.approval, c.run)
  end

  test "branch mode creates only the thread branch with an atomic absent-ref precondition", c do
    thread = Repo.update!(Ecto.Changeset.change(c.thread, ship_mode: :branch))
    approval = Repo.update!(Ecto.Changeset.change(c.approval, mode: :branch, target_branch: thread.branch))
    Agent.update(c.remote, fn _ -> nil end)
    assert {:ok, %{target_branch: target}} = Shipping.execute(thread, approval, c.run)
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
    assert {:error, :shipping_base_changed} = Shipping.execute(c.thread, c.approval, c.run)
  end

  test "unreviewed workspace edits invalidate approval", c do
    stub(Sandboxes, :exec, fn _, _, opts ->
      assert opts[:env] == %{}
      result(String.duplicate("e", 40))
    end)

    assert {:error, :shipping_review_stale} = Shipping.execute(c.thread, c.approval, c.run)
    assert Agent.get(c.remote, & &1) == @base
  end

  test "plain maps and revoked approvals cannot execute", c do
    assert {:error, :shipping_approval_invalid} = Shipping.execute(c.thread, Map.from_struct(c.approval), c.run)
    Repo.update!(Ecto.Changeset.change(c.approval, status: :failed))
    assert {:error, :shipping_approval_invalid} = Shipping.execute(c.thread, c.approval, c.run)
  end

  test "archiving and restoring a claimed Ship never revives its old worker", c do
    assert {:ok, _} = Tuist.Threads.archive(c.user, c.user.account, c.thread.id, "archived")
    assert Repo.reload!(c.run).status == "outcome_unknown"
    assert {:ok, _} = Tuist.Threads.archive(c.user, c.user.account, c.thread.id, "active")
    reject(Sandboxes, :exec, 3)
    reject(App, :create_scoped_installation_token, 3)
    assert {:error, :stale_run} = Shipping.execute(c.thread, c.approval, c.run)
    assert Agent.get(c.remote, & &1) == @base
  end

  test "losing ownership during final repository lookup prevents a ref write", c do
    for changes <- [
          [status: "outcome_unknown"],
          [attempt: c.run.attempt + 1],
          [heartbeat_at: DateTime.add(DateTime.utc_now(:second), -46)]
        ] do
      Repo.update!(
        Ecto.Changeset.change(Repo.reload!(c.run),
          status: "running",
          attempt: c.run.attempt,
          heartbeat_at: DateTime.utc_now(:second)
        )
      )

      stub(Req, :request, fn opts ->
        if opts[:method] == :get and URI.parse(opts[:url]).path == "/repos/Tuist/Example" do
          Repo.update!(Ecto.Changeset.change(Repo.reload!(c.run), changes))
        end

        c.broker.(opts)
      end)

      assert {:error, :stale_run} = Shipping.execute(c.thread, c.approval, c.run)
      assert Agent.get(c.remote, & &1) == @base
    end
  end

  test "a persisted guest-generated diff must match the trusted server review before publishing", c do
    stub(Repository, :review, fn _, _, _ -> {:ok, "actual unreviewed changes"} end)
    assert {:error, :shipping_review_stale} = Shipping.execute(c.thread, c.approval, c.run)
    assert Agent.get(c.remote, & &1) == @base
  end

  test "trusted review refuses an oversized GitHub response before decoding it", c do
    stub(Req, :request, fn opts ->
      plug = fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, String.duplicate("x", 8_388_609))
      end

      Mimic.call_original(Req, :request, [Keyword.put(opts, :plug, plug)])
    end)

    assert {:error, :shipping_review_unavailable} =
             Mimic.call_original(Repository, :review, [c.user.account, c.approval, c.objects])
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
    assert {:ok, _} = Shipping.execute(c.thread, c.approval, c.run)
  end

  test "PR-required rules and classic protections refuse even if the App could bypass them", c do
    stub(Req, :get, fn _ -> {:ok, %{status: 200, body: [%{"type" => "pull_request"}]}} end)
    assert {:error, :pull_request_required} = Shipping.execute(c.thread, c.approval, c.run)
    stub(Req, :get, fn _ -> {:ok, %{status: 200, body: []}} end)
    stub(Req, :post, fn _ -> policy([%{"pattern" => "m*"}]) end)
    assert {:error, :protected_branch} = Shipping.execute(c.thread, c.approval, c.run)
  end

  test "invalid exported bytes never reach a ref mutation", c do
    objects = put_in(c.objects, ["entries", Access.at(0), "content"], Base.encode64("unreviewed"))

    assert {:error, :shipping_objects_invalid} =
             Repository.ship(c.user.account, c.approval, fn -> {:ok, objects} end, fn -> :ok end)

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

    assert {:ok, %{head_sha: @head}} = Shipping.execute(c.thread, c.approval, c.run)
  end

  test "an unconfirmed mutation stays uncertain even when the destination still has its old head", c do
    for response <- [
          {:error, :timeout},
          {:ok, %{status: 200, body: %{"errors" => [%{"type" => "INTERNAL", "message" => "Operation interrupted"}]}}}
        ] do
      stub(Req, :post, fn opts ->
        if opts[:json][:variables][:input], do: response, else: policy([])
      end)

      assert {:error, :shipping_uncertain} = Shipping.execute(c.thread, c.approval, c.run)
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
    File.mkdir_p!(Path.join(root, "a"))
    File.write!(Path.join(root, "a/child"), "old child\n")
    File.write!(Path.join(root, "b"), "old file\n")
    git!(root, ["add", "."])
    git!(root, ["-c", "user.name=Test", "-c", "user.email=test@example.com", "commit", "-m", "base"])
    base = git!(root, ["rev-parse", "HEAD"])
    index = File.read!(Path.join(root, ".git/index"))
    File.write!(Path.join(root, "tracked"), "after\n")
    File.write!(Path.join(root, "new"), "new file\n")
    File.rm_rf!(Path.join(root, "a"))
    File.write!(Path.join(root, "a"), "replacement file\n")
    File.rm!(Path.join(root, "b"))
    File.mkdir_p!(Path.join(root, "b"))
    File.write!(Path.join(root, "b/child"), "replacement child\n")
    thread = Repo.update!(Ecto.Changeset.change(c.thread, base_sha: base))

    stub(Repository, :review, fn account, snapshot, objects ->
      Mimic.call_original(Repository, :review, [account, snapshot, objects])
    end)

    stub(Req, :request, fn opts ->
      assert {"authorization", "Bearer server-only-read-token"} in opts[:headers]
      assert opts[:method] == :get
      path = String.replace_prefix(URI.parse(opts[:url]).path, "/repos/Tuist/Example", "")
      {:ok, %{status: 200, body: base_response(root, path)}}
    end)

    stub(Sandboxes, :exec, fn _, argv, opts ->
      {output, code} =
        case argv do
          ["python3", "-c", script | args] ->
            assert opts[:env] == %{}
            System.cmd("python3", ["-c", String.replace(script, "/workspace", directory) | args], stderr_to_stdout: true)

          ["git" | _] ->
            {"forged benign guest diff", 0}
        end

      {:ok, %{stdout: output, stderr: "", exit_code: code}}
    end)

    assert {:ok, preview} = Shipping.preview(c.user, thread)
    assert preview.diff =~ "+after"
    assert preview.diff =~ "+new file"
    assert preview.diff =~ "+replacement file"
    assert preview.diff =~ "-old child"
    assert preview.diff =~ "+replacement child"
    assert preview.diff =~ "-old file"
    refute preview.diff =~ "forged benign"
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

  defp base_response(root, "/git/commits/" <> sha),
    do: %{"sha" => sha, "tree" => %{"sha" => git!(root, ["rev-parse", sha <> "^{tree}"])}}

  defp base_response(root, "/git/trees/" <> sha) do
    {output, 0} = System.cmd("git", ["ls-tree", "-r", "-t", "-z", sha], cd: root)

    entries =
      for entry <- String.split(output, <<0>>, trim: true) do
        [metadata, path] = String.split(entry, "\t", parts: 2)
        [mode, type, oid] = String.split(metadata, " ")
        %{"path" => path, "mode" => mode, "type" => type, "sha" => oid}
      end

    %{"sha" => sha, "truncated" => false, "tree" => entries}
  end

  defp base_response(root, "/git/blobs/" <> sha) do
    {bytes, 0} = System.cmd("git", ["cat-file", "blob", sha], cd: root)
    %{"sha" => sha, "encoding" => "base64", "size" => byte_size(bytes), "content" => Base.encode64(bytes)}
  end

  defp git!(root, args) do
    {output, 0} = System.cmd("git", args, cd: root, stderr_to_stdout: true)
    String.trim(output)
  end
end
