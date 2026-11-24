defmodule LuftServer.Notifications.Delegation do
  @moduledoc "Notification projections require the original conversation delegation and recipient sign-in."
  alias LuftServer.Sessions
  alias LuftServer.Tuist.Scope

  defmodule Actor do
    @moduledoc false
    @enforce_keys [:id, :session_id]
    defstruct [:id, :session_id]
  end

  def actor(session_id, user_id) do
    if active?(session_id, user_id), do: %Actor{id: user_id, session_id: session_id}
  end

  def active?(session_id, user_id) do
    case Sessions.get_by_id(session_id) do
      %{user_sub: subject} -> subject == to_string(user_id)
      _ -> false
    end
  end

  def readable?(thread, %Actor{id: user_id, session_id: recipient}) do
    # No lookup of a convenient sign-in for the same person: both the original
    # delegation and the receiving profile must still authorize this account.
    with true <- thread.owner_id == user_id,
         true <- is_binary(thread.account_handle),
         owner when not is_nil(owner) <- Sessions.get_by_id(thread.owner_session_id),
         true <- owner.user_sub == to_string(user_id),
         session when not is_nil(session) <- Sessions.get_by_id(recipient),
         true <- session.user_sub == to_string(user_id),
         {:ok, scope} <- Scope.load(owner, thread.account_handle),
         true <-
           scope.user_id == user_id and scope.account_id == thread.account_id and
             scope.can_create_threads,
         {:ok, scope} <- Scope.load(session, thread.account_handle) do
      scope.user_id == user_id and scope.account_id == thread.account_id and
        scope.can_create_threads
    else
      {:error, :tuist_unavailable} -> raise "Notification authorization temporarily unavailable"
      _ -> false
    end
  end

  def thread_title(%{title: title, goal: goal}) do
    title = title |> to_string() |> String.trim()

    if title == "" or title == String.trim(String.slice(to_string(goal), 0, 80)),
      do: "Your thread",
      else: String.slice(title, 0, 100)
  end
end
