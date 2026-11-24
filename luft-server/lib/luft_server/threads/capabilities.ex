defmodule LuftServer.Threads.Capabilities do
  @moduledoc "Account capabilities using only the workspace owner's exact delegated session."
  alias LuftServer.Config
  alias LuftServer.Sessions
  alias LuftServer.Tuist.Scope

  @errors ~w(workspace_busy busy not_found invalid_request unsupported_operation repository_not_authorized repository_access_denied github_identity_missing repository_access_unavailable repository_too_large checkout_too_large checkout_unavailable shipping_uncertain shipping_objects_invalid shipping_review_unavailable shipping_diff_empty_or_too_large stdin_offset_mismatch stdin_not_attached already_started timeout)a

  def owner(thread) do
    with session when not is_nil(session) <- Sessions.get_by_id(thread.owner_session_id),
         true <- session.user_sub == to_string(thread.owner_id),
         true <- is_binary(thread.account_handle) and thread.account_handle != "",
         {:ok, scope} <- Scope.load(session, thread.account_handle),
         true <-
           scope.account_id == thread.account_id and scope.user_id == thread.owner_id and
             scope.can_create_threads do
      {:ok,
       %{
         owner_session_id: session.id,
         owner_id: thread.owner_id,
         account_id: thread.account_id,
         account_handle: thread.account_handle
       }}
    else
      _ -> {:error, :delegation_unavailable}
    end
  end

  def request(owner, operation, params \\ %{}) do
    with {:ok, owner} <- owner(owner),
         session when not is_nil(session) <- Sessions.get_by_id(owner.owner_session_id),
         {:ok, token} <- Sessions.access_token(session),
         {:ok, response} <-
           Req.post(
             Config.tuist_issuer() <>
               "/api/accounts/" <>
               URI.encode(owner.account_handle, &URI.char_unreserved?/1) <>
               "/workspace-capabilities",
             Keyword.merge(Config.req_options(),
               auth: {:bearer, token},
               json: Map.put(params, :operation, operation),
               redirect: false,
               retry: false,
               receive_timeout: 650_000
             )
           ) do
      decode(response)
    else
      {:error, :delegation_unavailable} = error -> error
      _ -> {:error, :capability_outcome_unknown}
    end
  end

  defp decode(%{status: 200, body: %{"result" => result}}), do: {:ok, result}

  defp decode(%{status: status}) when status in [401, 403, 404],
    do: {:error, :delegation_unavailable}

  defp decode(%{body: %{"code" => code}}) do
    {:error, Enum.find(@errors, :capability_unavailable, &(Atom.to_string(&1) == code))}
  end

  defp decode(_), do: {:error, :capability_outcome_unknown}

  def sandbox(owner, operation, params) do
    with {:ok, data} when is_map(data) <- request(owner, operation, params) do
      {:ok,
       %{
         id: data["id"],
         account_id: data["account_id"],
         state: data["state"],
         residency_work_id: data["residency_work_id"],
         owner: owner
       }}
    end
  end

  def exec(sandbox, argv, opts \\ []) do
    with {:ok, data} <-
           request(
             sandbox.owner,
             "exec",
             Map.merge(Map.new(opts), %{sandbox_id: sandbox.id, argv: argv})
           ) do
      {:ok,
       %{exit_code: data["exit_code"], stdout: data["stdout"] || "", stderr: data["stderr"] || ""}}
    end
  end

  def command(sandbox, operation, id, params \\ %{}) do
    with {:ok, data} <-
           request(
             sandbox.owner,
             operation,
             Map.merge(params, %{sandbox_id: sandbox.id, command_id: id})
           ) do
      {:ok,
       Map.new(data, fn {key, value} ->
         known =
           Enum.find(
             ~w(status exit_code stdout stderr stdout_offset stderr_offset stdout_size stderr_size progress)a,
             &(Atom.to_string(&1) == key)
           )

         {known || key, value}
       end)}
    end
  end
end
