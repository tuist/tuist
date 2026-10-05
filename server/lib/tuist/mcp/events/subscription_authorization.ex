defmodule Tuist.MCP.Events.SubscriptionAuthorization do
  @moduledoc false

  alias Tuist.Accounts
  alias Tuist.Accounts.AuthenticatedAccount
  alias Tuist.Accounts.User
  alias Tuist.MCP.Authorization
  alias Tuist.MCP.Events.Catalog
  alias Tuist.Projects
  alias Tuist.Repo

  def authorized_target(conn, name, args) do
    case Catalog.target(name) do
      {:project, category} -> authorized_project(conn, args, category)
      {:account, :runners} -> authorized_account(conn, args)
      nil -> {:error, :unsupported_event}
    end
  end

  defp authorized_project(
         %{assigns: assigns} = conn,
         %{"account_handle" => account_handle, "project_handle" => project_handle} = args,
         category
       )
       when is_binary(account_handle) and is_binary(project_handle) and map_size(args) == 2 do
    with %AuthenticatedAccount{} = subject <- assigns[:current_subject],
         %User{} = user <- assigns[:current_user] || subject.issued_by,
         %Projects.Project{} = project <-
           Projects.get_project_by_account_and_project_handles(account_handle, project_handle),
         true <- member?(user, project.account),
         true <- Authorization.authorize(user, :read, project, category),
         true <- Authorization.authorize(subject, :read, project, category),
         {:ok, credential} <- credential(conn, user, subject) do
      {:ok, user, credential, %{account_id: project.account_id, project_id: project.id}}
    else
      _ -> {:error, :unauthorized}
    end
  end

  defp authorized_project(_conn, _args, _category), do: {:error, :invalid_arguments}

  defp authorized_account(%{assigns: assigns} = conn, %{"account_handle" => account_handle} = args)
       when is_binary(account_handle) and map_size(args) == 1 do
    with %AuthenticatedAccount{} = subject <- assigns[:current_subject],
         %User{} = user <- assigns[:current_user] || subject.issued_by,
         %Accounts.Account{} = account <- Accounts.get_account_by_handle(account_handle),
         true <- member?(user, account),
         true <- Authorization.authorize(user, :read, account, :runners),
         true <- Authorization.authorize(subject, :read, account, :runners),
         {:ok, credential} <- credential(conn, user, subject) do
      {:ok, user, credential, %{account_id: account.id, project_id: nil}}
    else
      _ -> {:error, :unauthorized}
    end
  end

  defp authorized_account(_conn, _args), do: {:error, :invalid_arguments}

  defp member?(user, account) do
    Accounts.owns_account_or_is_member_of_account_organization?(user, Repo.preload(account, :organization))
  end

  defp credential(_conn, _user, %AuthenticatedAccount{token_id: token_id}) when not is_nil(token_id),
    do: {:ok, %{account_token_id: token_id}}

  defp credential(conn, %User{id: user_id}, %AuthenticatedAccount{issued_by: %User{id: user_id}}) do
    with ["Bearer " <> token] <- Plug.Conn.get_req_header(conn, "authorization"),
         {:ok, %{"client_id" => client_id, "user_id" => ^user_id}} <- Tuist.Guardian.decode_and_verify(token),
         {:ok, _} <- Ecto.UUID.cast(client_id) do
      {:ok, %{oauth_client_id: client_id}}
    else
      _ -> {:error, :unauthorized}
    end
  end

  defp credential(_conn, _user, _subject), do: {:error, :unauthorized}
end
