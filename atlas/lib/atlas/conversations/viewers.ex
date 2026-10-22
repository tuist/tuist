defmodule Atlas.Conversations.Viewers do
  @moduledoc """
  Who is looking at a conversation, and who is typing.

  Mirrors `Atlas.Presence`: one 20-second lease per connection, renewed by the
  channel, expiring by PostgreSQL's clock. Typing is a timestamp on that lease
  that lapses after eight seconds without a refresh. Drafts never reach the
  server. Leases are not audited and are not history.
  """

  import Ecto.Query

  alias Atlas.Conversations
  alias Atlas.Conversations.Access
  alias Atlas.Conversations.Conversation
  alias Atlas.Conversations.Viewer
  alias Atlas.Repo
  alias Atlas.Users.User

  @typing_seconds 8

  def typing_seconds, do: @typing_seconds

  def enter(%Conversation{id: conversation_id}, %User{id: user_id}, connection_id) do
    Repo.insert_all(
      Viewer,
      [%{connection_id: connection_id, conversation_id: conversation_id, user_id: user_id}],
      conflict_target: [:connection_id],
      on_conflict:
        from(viewer in Viewer, update: [set: [expires_at: fragment("clock_timestamp() + interval '20 seconds'")]])
    )

    Conversations.notify_changed(conversation_id)
    :ok
  end

  def renew(%Conversation{} = conversation, %User{} = user, connection_id) do
    {count, _} =
      Repo.update_all(
        from(viewer in Viewer,
          where: viewer.connection_id == ^connection_id,
          update: [set: [expires_at: fragment("clock_timestamp() + interval '20 seconds'")]]
        ),
        []
      )

    if count == 0, do: enter(conversation, user, connection_id), else: :ok
  end

  def typing(conversation_id, connection_id, typing?) do
    query =
      if typing? do
        from viewer in Viewer,
          where: viewer.connection_id == ^connection_id,
          update: [set: [typing_until: fragment("clock_timestamp() + make_interval(secs => ?)", ^@typing_seconds)]]
      else
        from viewer in Viewer,
          where: viewer.connection_id == ^connection_id and not is_nil(viewer.typing_until),
          update: [set: [typing_until: nil]]
      end

    {count, _} = Repo.update_all(query, [])
    if count > 0, do: Conversations.notify_changed(conversation_id)
    :ok
  end

  def leave(conversation_id, connection_id) do
    {count, _} = Repo.delete_all(from viewer in Viewer, where: viewer.connection_id == ^connection_id)
    if count > 0, do: Conversations.notify_changed(conversation_id)
    :ok
  end

  @doc "Removes expired leases and notifies affected conversations."
  def prune do
    {_count, conversation_ids} =
      Repo.delete_all(
        from viewer in Viewer,
          where: viewer.expires_at <= fragment("clock_timestamp()"),
          select: viewer.conversation_id
      )

    conversation_ids |> Enum.uniq() |> Enum.each(&Conversations.notify_changed/1)
    :ok
  end

  defp agent_status(conversation) do
    case Conversations.active_run(conversation) do
      nil -> if Conversations.agent_configured?(), do: "idle", else: "unconfigured"
      run -> run.status
    end
  end

  @doc """
  `%{revision, people, agent_status}` where people are participants who can currently read
  the conversation and hold a live lease, including the caller.
  """
  def snapshot(%Conversation{id: conversation_id} = conversation) do
    conversation = Repo.get(Conversation, conversation_id) || conversation
    readers = conversation |> Access.audience() |> Map.new(&{&1.id, &1})

    people =
      Repo.all(
        from viewer in Viewer,
          where: viewer.conversation_id == ^conversation_id and viewer.expires_at > fragment("clock_timestamp()"),
          group_by: viewer.user_id,
          select: {viewer.user_id, fragment("bool_or(coalesce(? > clock_timestamp(), false))", viewer.typing_until)}
      )
      |> Enum.flat_map(fn {user_id, typing?} ->
        case Map.fetch(readers, user_id) do
          {:ok, user} -> [%{id: user.id, name: Conversations.display_name(user), typing: typing?}]
          :error -> []
        end
      end)
      |> Enum.sort_by(&{&1.name, &1.id})

    %{revision: conversation.last_seq, people: people, agent_status: agent_status(conversation)}
  end
end
