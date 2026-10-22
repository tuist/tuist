defmodule Atlas.Conversations.Access do
  @moduledoc """
  Who may read a conversation and what the assistant may do inside it.

  A participant can read a conversation only while they hold every scope in
  its `required_scopes`. That set is a ratchet: each successful tool call adds
  the scopes its output required, so privileged output only ever exists where
  every reader is allowed to see it, and people added later must already hold
  those scopes.

  The audience of a run is the set of participants who can currently read the
  conversation. The assistant's effective scopes are the intersection of the
  audience's scopes, so a tool is available only when everyone who will see its
  output could have called it themselves. The acting user must be part of the
  audience. Everything here is evaluated against current database state on each
  call, never cached for the lifetime of a run.
  """

  import Ecto.Query

  alias Atlas.Conversations.Conversation
  alias Atlas.Conversations.Participant
  alias Atlas.Repo
  alias Atlas.Users
  alias Atlas.Users.User

  def can_read?(%Conversation{} = conversation, %User{} = user) do
    participant?(conversation, user) and holds_all?(user, conversation.required_scopes)
  end

  def can_read?(_conversation, _user), do: false

  def participant?(%Conversation{id: conversation_id}, %User{id: user_id}) do
    Repo.exists?(
      from participant in Participant,
        where: participant.conversation_id == ^conversation_id and participant.user_id == ^user_id
    )
  end

  def holds_all?(%User{}, []), do: true

  def holds_all?(%User{} = user, scopes) when is_list(scopes) do
    granted = MapSet.new(Users.scopes_for(user))
    Enum.all?(scopes, &MapSet.member?(granted, &1))
  end

  @doc "Participants who can currently read the conversation."
  def audience(%Conversation{} = conversation) do
    conversation
    |> participants()
    |> Enum.filter(&holds_all?(&1, conversation.required_scopes))
  end

  def participants(%Conversation{id: conversation_id}) do
    Repo.all(
      from user in User,
        join: participant in Participant,
        on: participant.user_id == user.id,
        where: participant.conversation_id == ^conversation_id,
        order_by: [asc: participant.inserted_at, asc: user.id]
    )
  end

  @doc "Scopes held by every member of `audience`."
  def effective_scopes([]), do: MapSet.new()

  def effective_scopes(audience) when is_list(audience) do
    audience
    |> Enum.map(&MapSet.new(Users.scopes_for(&1)))
    |> Enum.reduce(&MapSet.intersection/2)
  end

  @doc """
  Authorizes the assistant acting as `acting_user` to use a tool that requires
  `scopes`. Returns `{:ok, audience}` or `{:error, reason}` where reason is
  `:acting_user_unavailable` or `:audience_lacks_access`.
  """
  def authorize_tool(%Conversation{} = conversation, %User{} = acting_user, scopes) when is_list(scopes) do
    audience = audience(conversation)

    cond do
      not Enum.any?(audience, &(&1.id == acting_user.id)) ->
        {:error, :acting_user_unavailable}

      not Enum.all?(scopes, &MapSet.member?(effective_scopes(audience), &1)) ->
        {:error, :audience_lacks_access}

      true ->
        {:ok, audience}
    end
  end

  def authorize_tool(_conversation, _acting_user, _scopes), do: {:error, :acting_user_unavailable}
end
