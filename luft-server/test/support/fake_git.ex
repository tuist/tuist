defmodule LuftServer.FakeGit do
  @moduledoc "Loopback Enroute protocol fixture; repository data never leaves the test process tree."
  alias LuftServer.Git.Enroute.Api.V1alpha1, as: API
  alias LuftServer.Git.Enroute.Common.V1alpha1, as: Common

  def start_link(_), do: Agent.start_link(fn -> %{} end, name: __MODULE__)
  def child_spec(opts), do: %{id: __MODULE__, start: {__MODULE__, :start_link, [opts]}}

  def call(operation, request) do
    if operation in [:object, :fork] do
      hook =
        Agent.get_and_update(
          __MODULE__,
          &Map.pop(&1, if(operation == :object, do: :on_object, else: :on_fork))
        )

      if hook, do: hook.()
    end

    case Agent.get_and_update(__MODULE__, &handle(&1, operation, request)) do
      {:error, status} -> raise GRPC.RPCError, status: status
      result -> result
    end
  end

  defp handle(state, :create, %{repo: repo}) do
    state = Map.put_new(state, repo.key, %{refs: %{}, commits: %{}, blobs: %{}})
    {%API.CreateRepositoryResponse{repository: %API.Repository{repo: repo}}, state}
  end

  defp handle(state, operation, %{repo: repo} = request) do
    case state[repo.key] do
      nil -> {{:error, 5}, state}
      data -> handle_repo(state, data, operation, request)
    end
  end

  defp handle_repo(state, _data, :get, %{repo: repo}) do
    {%API.GetRepositoryResponse{repository: %API.Repository{repo: repo}}, state}
  end

  defp handle_repo(state, data, :refs, request) do
    refs =
      for {name, id} <- data.refs,
          Enum.any?(request.prefixes, &String.starts_with?(name, &1)),
          do: %API.Ref{name: name, object_id: %Common.ObjectId{hex: id}}

    {%API.ListRefsResponse{refs: refs}, state}
  end

  defp handle_repo(state, data, :fork, %{repo: repo, updates: [update]}) do
    current = data.refs[update.refname]
    expected = update.old_object_id && update.old_object_id.hex

    if current != expected do
      {%API.UpdateRefsResponse{
         outcomes: [
           %API.RefUpdateOutcome{
             refname: update.refname,
             rejection: %API.RefUpdateOutcome.Rejection{reason: :REASON_NON_FAST_FORWARD}
           }
         ]
       }, state}
    else
      next = put_in(state, [repo.key, :refs, update.refname], update.new_object_id.hex)

      if update.refname == "refs/heads/main" and state[:lose_merge_response] do
        {{:error, 14}, Map.delete(next, :lose_merge_response)}
      else
        {%API.UpdateRefsResponse{outcomes: [%API.RefUpdateOutcome{refname: update.refname}]},
         next}
      end
    end
  end

  defp handle_repo(state, data, :ancestor, request) do
    {%API.IsAncestorResponse{
       is_ancestor:
         ancestor?(data, request.ancestor_commit_id.hex, request.descendant_commit_id.hex)
     }, state}
  end

  defp handle_repo(state, data, :commit, request) do
    parent = data.refs[request.branch]
    expected = request.expected_old_commit.expectation

    matches =
      (is_nil(parent) and match?({:absent, _}, expected)) or
        match?({:commit_id, %Common.ObjectId{hex: ^parent}}, expected)

    if matches do
      [%{path: path, change: {:put, %{content: bytes}}}] = request.changes
      blob = hash("blob #{byte_size(bytes)}\0" <> bytes)
      commit = hash(bytes <> request.branch <> (parent || ""))
      tree = if parent, do: data.commits[parent].tree, else: %{}

      state =
        state
        |> put_in([request.repo.key, :blobs, blob], bytes)
        |> put_in([request.repo.key, :commits, commit], %{
          tree: Map.put(tree, path, blob),
          parent: parent
        })
        |> put_in([request.repo.key, :refs, request.branch], commit)

      {%API.CreateCommitResponse{commit_id: %Common.ObjectId{hex: commit}}, state}
    else
      {{:error, 9}, state}
    end
  end

  defp handle_repo(state, data, :tree, request) do
    case data.commits[request.object_id.hex] do
      nil ->
        {{:error, 5}, state}

      %{tree: tree} ->
        {[
           %API.ListTreeResponse{
             entries:
               for(
                 {path, blob} <- tree,
                 do: %API.TreeEntry{
                   path: path,
                   kind: :OBJECT_KIND_BLOB,
                   object_id: %Common.ObjectId{hex: blob}
                 }
               )
           }
         ], state}
    end
  end

  defp handle_repo(state, data, :object, request) do
    case data.blobs[request.object_id.hex] do
      nil ->
        {{:error, 5}, state}

      bytes ->
        {[
           %API.GetObjectResponse{
             chunk: {:header, %API.ObjectHeader{kind: :OBJECT_KIND_BLOB, size: byte_size(bytes)}}
           },
           %API.GetObjectResponse{chunk: {:data, bytes}}
         ], state}
    end
  end

  defp hash(bytes), do: :crypto.hash(:sha, bytes) |> Base.encode16(case: :lower)

  defp ancestor?(data, ancestor, descendant) do
    case data.commits[descendant] do
      nil -> false
      _ when ancestor == descendant -> true
      %{parent: nil} -> false
      %{parent: parent} -> ancestor?(data, ancestor, parent)
    end
  end
end

defmodule LuftServer.FakeGit.Repositories do
  use GRPC.Server, service: LuftServer.Git.Enroute.Api.V1alpha1.RepositoryService.Service
  def create_repository(request, _stream), do: LuftServer.FakeGit.call(:create, request)
  def get_repository(request, _stream), do: LuftServer.FakeGit.call(:get, request)
end

defmodule LuftServer.FakeGit.Commits do
  use GRPC.Server, service: LuftServer.Git.Enroute.Api.V1alpha1.CommitService.Service
  def create_commit(request, _stream), do: LuftServer.FakeGit.call(:commit, request)
end

defmodule LuftServer.FakeGit.Refs do
  use GRPC.Server, service: LuftServer.Git.Enroute.Api.V1alpha1.RefService.Service
  def list_refs(request, _stream), do: LuftServer.FakeGit.call(:refs, request)
  def update_refs(request, _stream), do: LuftServer.FakeGit.call(:fork, request)
  # The generated gRPC service requires this callback name.
  # credo:disable-for-next-line Credo.Check.Readability.PredicateFunctionNames
  def is_ancestor(request, _stream), do: LuftServer.FakeGit.call(:ancestor, request)
end

defmodule LuftServer.FakeGit.Objects do
  use GRPC.Server, service: LuftServer.Git.Enroute.Api.V1alpha1.ObjectService.Service

  def list_tree(request, stream),
    do: send_replies(stream, LuftServer.FakeGit.call(:tree, request))

  def get_object(request, stream),
    do: send_replies(stream, LuftServer.FakeGit.call(:object, request))

  defp send_replies(stream, replies) do
    Enum.each(replies, &GRPC.Server.send_reply(stream, &1))
    stream
  end
end

defmodule LuftServer.FakeGit.Endpoint do
  use GRPC.Endpoint
  run(LuftServer.FakeGit.Repositories)
  run(LuftServer.FakeGit.Commits)
  run(LuftServer.FakeGit.Refs)
  run(LuftServer.FakeGit.Objects)
end
