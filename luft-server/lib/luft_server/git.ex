defmodule LuftServer.Git do
  @moduledoc """
  Private Git storage for authorized behavior proposals. Callers must check the
  current scope and workspace grants before calling, and recheck before saving.
  Tuist owns organizations; this table maps each to its ops repository,
  not its separate project repositories.
  """
  alias LuftServer.Git.Enroute.Api.V1alpha1, as: API
  alias LuftServer.Git.Enroute.Common.V1alpha1, as: Common
  alias LuftServer.Git.OpsRepository
  alias LuftServer.Repo

  @limit 262_144

  def main(scope) do
    with_channel(fn channel, opts ->
      case Repo.get_by(OpsRepository, organization_id: scope.organization_id) do
        nil ->
          {:ok, nil}

        mapping ->
          case tip(channel, opts, %Common.RepoKey{key: mapping.id}, "refs/heads/main") do
            {:ok, id} -> {:ok, id && id.hex}
            {:error, %GRPC.RPCError{status: 5}} -> {:ok, nil}
            error -> error
          end
      end
    end)
  end

  def merge(scope, snapshot, pin) do
    with_channel(fn channel, opts ->
      with {:ok, _} <- verify_on(channel, opts, scope, snapshot, pin),
           repo = %Common.RepoKey{key: pin["repository_key"]},
           {:ok, head} <- tip(channel, opts, repo, "refs/heads/main") do
        cond do
          head && head.hex == pin["commit_id"] ->
            {:ok, pin}

          (head && head.hex) == snapshot["base_commit_id"] ->
            advance_main(channel, opts, repo, head, pin)

          true ->
            merged_on(channel, opts, scope, snapshot, pin, head)
        end
      end
    end)
  end

  def merged(scope, snapshot, pin) do
    with_channel(fn channel, opts ->
      with {:ok, _} <- verify_on(channel, opts, scope, snapshot, pin),
           repo = %Common.RepoKey{key: pin["repository_key"]},
           {:ok, head} <- tip(channel, opts, repo, "refs/heads/main") do
        merged_on(channel, opts, scope, snapshot, pin, head)
      end
    end)
  end

  defp advance_main(channel, opts, repo, head, pin) do
    with :ok <- ancestor(channel, opts, repo, head, %Common.ObjectId{hex: pin["commit_id"]}),
         {:ok, %{outcomes: [%{refname: "refs/heads/main", rejection: nil}]}} <-
           API.RefService.Stub.update_refs(
             channel,
             %API.UpdateRefsRequest{
               repo: repo,
               atomic: true,
               updates: [
                 %API.RefUpdate{
                   refname: "refs/heads/main",
                   old_object_id: head,
                   new_object_id: %Common.ObjectId{hex: pin["commit_id"]}
                 }
               ]
             },
             opts
           ) do
      {:ok, pin}
    else
      {:error, %GRPC.RPCError{} = error} -> {:error, error}
      _ -> {:error, :revision_conflict}
    end
  end

  defp merged_on(_channel, _opts, _scope, _snapshot, _pin, nil), do: {:error, :revision_conflict}

  defp merged_on(channel, opts, scope, snapshot, pin, head) do
    repo = %Common.RepoKey{key: pin["repository_key"]}

    with :ok <- ancestor(channel, opts, repo, %Common.ObjectId{hex: pin["commit_id"]}, head),
         {:ok, _} <-
           verify_on(channel, opts, scope, snapshot, Map.put(pin, "commit_id", head.hex)) do
      {:ok, pin}
    end
  end

  defp ancestor(_channel, _opts, _repo, nil, _descendant), do: :ok

  defp ancestor(channel, opts, repo, ancestor, descendant) do
    case API.RefService.Stub.is_ancestor(
           channel,
           %API.IsAncestorRequest{
             repo: repo,
             ancestor_commit_id: ancestor,
             descendant_commit_id: descendant
           },
           opts
         ) do
      {:ok, %{is_ancestor: true}} -> :ok
      {:error, _} = error -> error
      _ -> {:error, :revision_conflict}
    end
  end

  defp path(scope), do: "accounts/#{scope.account_id}/release.json"

  def publish(scope, snapshot, parent, existing) when is_integer(scope.organization_id) do
    with_channel(fn channel, opts ->
      if existing do
        verify_on(channel, opts, scope, snapshot, existing)
      else
        with {:ok, mapping} <- mapping(scope.organization_id),
             repo = %Common.RepoKey{key: mapping.id},
             {:ok, _} <-
               API.RepositoryService.Stub.create_repository(
                 channel,
                 %API.CreateRepositoryRequest{repo: repo},
                 opts
               ),
             {:ok, commit} <- publish_on(channel, opts, scope, repo, snapshot, parent) do
          verify_on(channel, opts, scope, snapshot, %{
            "repository_key" => mapping.id,
            "commit_id" => commit.hex
          })
        end
      end
    end)
  end

  def verify(scope, snapshot, pin) do
    with_channel(&verify_on(&1, &2, scope, snapshot, pin))
  end

  defp mapping(organization) do
    Repo.insert(%OpsRepository{organization_id: organization},
      on_conflict: {:replace, [:organization_id]},
      conflict_target: [:organization_id],
      returning: true
    )
  end

  defp publish_on(channel, opts, scope, repo, snapshot, parent) do
    branch = "refs/heads/releases/#{scope.account_id}/#{snapshot["hash"]}"

    with {:ok, tip} <- tip(channel, opts, repo, branch),
         {:ok, tip} <- fork(channel, opts, repo, branch, tip, parent) do
      if tip && tip.hex != parent do
        {:ok, tip}
      else
        expected =
          if tip,
            do: %API.ExpectedOldCommit{expectation: {:commit_id, tip}},
            else: %API.ExpectedOldCommit{expectation: {:absent, %API.ExpectedOldCommit.Absent{}}}

        request = %API.CreateCommitRequest{
          repo: repo,
          branch: branch,
          expected_old_commit: expected,
          message: "Propose behavior release #{snapshot["hash"]}",
          author: %API.Identity{
            name: "Luft user #{scope.user_id}",
            email: "user-#{scope.user_id}@luft.invalid"
          },
          changes: [
            %API.PathChange{
              path: path(scope),
              change: {:put, %API.PutFile{content: Jason.encode!(snapshot)}}
            }
          ]
        }

        case API.CommitService.Stub.create_commit(channel, request, opts) do
          {:ok, result} -> {:ok, result.commit_id}
          # A concurrent proposer may have won. Inspect, never append blindly.
          {:error, %GRPC.RPCError{status: 9}} -> tip(channel, opts, repo, branch)
          error -> error
        end
      end
    end
  end

  defp fork(channel, opts, repo, branch, nil, parent) when is_binary(parent) do
    with {:ok, _} <-
           API.RefService.Stub.update_refs(
             channel,
             %API.UpdateRefsRequest{
               repo: repo,
               atomic: true,
               updates: [
                 %API.RefUpdate{refname: branch, new_object_id: %Common.ObjectId{hex: parent}}
               ]
             },
             opts
           ),
         {:ok, tip} when not is_nil(tip) <- tip(channel, opts, repo, branch) do
      {:ok, tip}
    else
      _ -> {:error, :revision_conflict}
    end
  end

  defp fork(_channel, _opts, _repo, _branch, tip, _parent), do: {:ok, tip}

  defp tip(channel, opts, repo, branch) do
    with {:ok, result} <-
           API.RefService.Stub.list_refs(
             channel,
             %API.ListRefsRequest{repo: repo, prefixes: [branch]},
             opts
           ) do
      {:ok, Enum.find_value(result.refs, &if(&1.name == branch, do: &1.object_id))}
    end
  end

  defp verify_on(channel, opts, scope, snapshot, pin) do
    with %OpsRepository{id: key} <-
           Repo.get_by(OpsRepository, organization_id: scope.organization_id),
         true <- pin["repository_key"] == key,
         commit when is_binary(commit) <- pin["commit_id"],
         true <- Regex.match?(~r/\A[0-9a-f]{40}\z/, commit),
         repo = %Common.RepoKey{key: key},
         {:ok, batches} <-
           API.ObjectService.Stub.list_tree(
             channel,
             %API.ListTreeRequest{repo: repo, object_id: %Common.ObjectId{hex: commit}},
             opts
           ),
         {:ok, object} <- snapshot_object(batches, path(scope)),
         {:ok, chunks} <-
           API.ObjectService.Stub.get_object(
             channel,
             %API.GetObjectRequest{repo: repo, object_id: object},
             opts
           ),
         {:ok, bytes} <- content(chunks),
         {:ok, ^snapshot} <- Jason.decode(bytes) do
      {:ok, pin}
    else
      {:error, %GRPC.RPCError{}} -> {:error, :unavailable}
      _ -> {:error, :revision_conflict}
    end
  end

  defp snapshot_object(batches, path) do
    Enum.reduce_while(batches, {:error, :revision_conflict}, fn
      {:error, %GRPC.RPCError{}} = error, _ ->
        {:halt, error}

      {:ok, %{entries: entries, truncated: false}}, result ->
        case Enum.find(entries, &(&1.path == path and &1.kind == :OBJECT_KIND_BLOB)) do
          nil -> {:cont, result}
          entry -> {:halt, {:ok, entry.object_id}}
        end

      _, _ ->
        {:halt, {:error, :revision_conflict}}
    end)
  end

  defp content(chunks) do
    Enum.reduce_while(chunks, {:ok, ""}, fn
      {:error, %GRPC.RPCError{}} = error, _ ->
        {:halt, error}

      {:ok, %{chunk: {:header, %{size: size, kind: :OBJECT_KIND_BLOB}}}}, {:ok, ""}
      when size <= @limit ->
        {:cont, {:ok, ""}}

      {:ok, %{chunk: {:data, data}}}, {:ok, bytes}
      when byte_size(bytes) + byte_size(data) <= @limit ->
        {:cont, {:ok, bytes <> data}}

      _, _ ->
        {:halt, {:error, :revision_conflict}}
    end)
  end

  defp with_channel(fun) do
    case Application.get_env(:luft_server, :git_endpoint) do
      endpoint when is_binary(endpoint) ->
        case GRPC.Stub.connect(endpoint, adapter_opts: [connect_timeout: 2_000, retry: 0]) do
          {:ok, channel} ->
            try do
              case fun.(channel, timeout: 2_000) do
                {:error, %GRPC.RPCError{}} -> {:error, :unavailable}
                result -> result
              end
            after
              GRPC.Stub.disconnect(channel)
            end

          _ ->
            {:error, :unavailable}
        end

      _ ->
        {:error, :unavailable}
    end
  rescue
    _ -> {:error, :unavailable}
  catch
    :exit, _ -> {:error, :unavailable}
  end
end
