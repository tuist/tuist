defmodule LuftServer.Threads.Execution do
  @moduledoc "Admission through the owner's and author's exact Luft delegations, before work is queued."

  alias LuftServer.Sessions
  alias LuftServer.Threads.Checkout
  alias LuftServer.Threads.Provider
  alias LuftServer.Threads.Repository
  alias LuftServer.Threads.Runners
  alias LuftServer.Tuist.Scope

  def admit(scope, owner, author, selection) do
    with %{account_handle: handle} when is_binary(handle) <- selection,
         %{id: owner_id} = owner <- live(owner),
         %{id: _} = author <- live(author),
         true <- author.user_sub == to_string(scope.user_id),
         {:ok, owner_scope} <- Scope.load(owner, handle),
         true <- owner_scope.account_id == scope.account_id and owner_scope.can_create_threads,
         {:ok, author_scope} <- Scope.load(author, handle),
         true <-
           author_scope.account_id == scope.account_id and author_scope.user_id == scope.user_id,
         :ok <- Provider.validate_model(owner, selection.provider, selection.model),
         owner_context = %{
           owner_id: owner_scope.user_id,
           owner_session_id: owner_id,
           account_id: scope.account_id,
           account_handle: handle
         },
         {:ok, selection} <- repository(owner_context, selection),
         :ok <- runner(owner, handle, selection) do
      {:ok, selection}
    else
      {:error, _} = error -> error
      _ -> {:error, :delegation_required}
    end
  end

  defp live(%{id: id, user_sub: subject}) do
    case Sessions.get_by_id(id) do
      %{user_sub: ^subject} = session -> session
      _ -> nil
    end
  end

  defp live(_), do: nil

  defp repository(_owner, %{repository: nil} = selection),
    do: {:ok, %{selection | base_branch: nil}}

  defp repository(owner, selection) do
    with {:ok, repository} <- Repository.authorize(owner, selection.repository),
         :ok <- Checkout.fits(repository),
         branch = selection.base_branch || repository.default_branch,
         true <-
           is_binary(branch) and byte_size(branch) in 1..255 and
             Regex.match?(~r/\A[\w][\w.\/-]*\z/u, branch) and
             not String.contains?(branch, ["..", "//", "@{"]) do
      {:ok, %{selection | repository: repository.name, base_branch: branch}}
    else
      false -> {:error, :invalid_arguments}
      error -> error
    end
  end

  defp runner(_owner, _handle, %{runner_id: nil}), do: :ok

  defp runner(owner, handle, %{repository: nil, runner_id: id}) do
    case Runners.usable(owner, handle, id) do
      {:ok, _runner} -> :ok
      error -> error
    end
  end

  defp runner(_owner, _handle, _selection), do: {:error, :invalid_arguments}
end
