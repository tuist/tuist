defmodule Tuist.VCS.PublicationsTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  import TuistTestSupport.Fixtures.AccountsFixtures
  import TuistTestSupport.Fixtures.VCSFixtures

  alias Tuist.GitHub.App
  alias Tuist.GitHub.Client
  alias Tuist.VCS.Publication
  alias Tuist.VCS.Publications
  alias Tuist.VCS.RepositoryBroker

  @base String.duplicate("a", 40)
  @empty "4b825dc642cb6eb9a060e54bf8d69288fbee4904"

  setup do
    user = user_fixture()
    github_app_installation_fixture(account: user)
    oauth2_identity_fixture(user: user, provider: :github, id_in_provider: "42")
    stub(Client, :get_user_by_id, fn _ -> {:ok, %Tuist.VCS.User{username: "owner"}} end)
    stub(Client, :get_repository_permission, fn _ -> {:ok, "write"} end)

    stub(Client, :list_installation_repositories, fn _, _ ->
      {:ok, %{meta: %{next_url: nil}, repositories: [%{full_name: "Tuist/Example", default_branch: "main"}]}}
    end)

    stub(App, :create_scoped_installation_token, fn _, _, _ -> {:ok, %{token: "server-only"}} end)
    id = Ecto.UUID.generate()
    blob = hash("blob", "new\n")
    tree = hash("tree", "100644 file" <> <<0>> <> Base.decode16!(blob, case: :lower))
    identity = "Tuist Threads <threads@tuist.dev> 946684800 +0000"

    head =
      hash("commit", "tree #{tree}\nparent #{@base}\nauthor #{identity}\ncommitter #{identity}\n\nTuist Threads #{id}\n")

    snapshot = %{
      thread_id: id,
      repository: "Tuist/Example",
      base_sha: @base,
      head_sha: head,
      target_branch: "main",
      mode: :direct
    }

    objects = %{
      "tree_sha" => tree,
      "entries" => [
        %{"path" => "file", "mode" => "100644", "type" => "blob", "sha" => blob, "content" => Base.encode64("new\n")}
      ]
    }

    stub(Req, :request, fn opts ->
      path = URI.parse(opts[:url]).path

      result =
        case {opts[:method], path} do
          {:get, "/repos/Tuist/Example/git/commits/" <> @base} ->
            {200, %{"sha" => @base, "tree" => %{"sha" => @empty}}}

          {:get, "/repos/Tuist/Example/git/trees/" <> @empty} ->
            {200, %{"sha" => @empty, "truncated" => false, "tree" => []}}

          {:get, "/repos/Tuist/Example/git/ref/heads/main"} ->
            {200, %{"object" => %{"sha" => @base}}}

          {:get, "/repos/Tuist/Example"} ->
            {200, %{"node_id" => "repository"}}

          {:post, "/repos/Tuist/Example/git/blobs"} ->
            {201, %{"sha" => blob}}

          {:post, "/repos/Tuist/Example/git/trees"} ->
            {201, %{"sha" => tree}}

          {:post, "/repos/Tuist/Example/git/commits"} ->
            {201, %{"sha" => head}}
        end

      {status, body} = result
      {:ok, %Req.Response{status: status, body: body}}
    end)

    stub(Req, :get, fn _ -> {:ok, %Req.Response{status: 200, body: []}} end)

    stub(Req, :post, fn opts ->
      if String.contains?(opts[:json].query, "UpdateRefsInput") do
        # This must be committed before the remote ref mutation is attempted.
        assert Repo.aggregate(Publication, :count) == 1
        update = hd(opts[:json].variables.input.refUpdates)
        assert update.beforeOid == @base
        assert update.afterOid == head
        assert update.force == false
        send(self(), :ref_write)
        {:error, :timeout}
      else
        {:ok,
         %Req.Response{
           status: 200,
           body: %{"data" => %{"repository" => %{"branchProtectionRules" => %{"totalCount" => 0, "nodes" => []}}}}
         }}
      end
    end)

    {:ok, diff} = RepositoryBroker.review(user.account, snapshot, objects)
    %{user: user, snapshot: snapshot, objects: objects, diff: diff, request: Ecto.UUID.generate()}
  end

  test "an uncertain write is never retried, even by an identical request; reconciliation is positive only", c do
    assert {:error, :shipping_uncertain} = publish(c)
    assert_received :ref_write
    assert {:error, :shipping_uncertain} = publish(c)
    refute_received :ref_write
    assert {:error, :shipping_uncertain} = Publications.reconcile(c.user.account, c.user, c.request)

    stub(Req, :request, fn opts ->
      assert opts[:method] == :get
      assert URI.parse(opts[:url]).path == "/repos/Tuist/Example/git/ref/heads/main"
      {:ok, %Req.Response{status: 200, body: %{"object" => %{"sha" => c.snapshot.head_sha}}}}
    end)

    assert {:ok, %{head_sha: head}} = publish(c)
    assert head == c.snapshot.head_sha
    assert Repo.one!(Publication).status == "succeeded"
    refute_received :ref_write
  end

  test "changed replay payloads, foreign users and foreign accounts never inherit the authorization", c do
    assert {:error, :shipping_uncertain} = publish(c)
    assert_received :ref_write
    assert {:error, :request_conflict} = publish(%{c | diff: "different"})
    stranger = user_fixture()
    assert {:error, :shipping_uncertain} = Publications.reconcile(c.user.account, stranger, c.request)
    assert {:error, :shipping_uncertain} = Publications.reconcile(stranger.account, stranger, c.request)
    refute_received :ref_write
  end

  test "lost GitHub permission blocks first publication without creating an authorization", c do
    stub(Client, :get_repository_permission, fn _ -> {:ok, "read"} end)
    assert {:error, :repository_access_denied} = publish(c)
    assert Repo.aggregate(Publication, :count) == 0
    refute_received :ref_write
  end

  defp publish(c), do: Publications.publish(c.user.account, c.user, c.request, c.snapshot, c.objects, c.diff)

  defp hash(type, bytes),
    do: Base.encode16(:crypto.hash(:sha, [type, " ", to_string(byte_size(bytes)), <<0>>, bytes]), case: :lower)
end
