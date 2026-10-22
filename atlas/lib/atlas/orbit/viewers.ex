defmodule Atlas.Orbit.Viewers do
  @moduledoc """
  Who is looking at a thread, and who is typing.

  Mirrors `Atlas.Presence`: one 20-second lease per connection, renewed by the
  channel, expiring by PostgreSQL's clock. Typing is a timestamp on that lease
  that lapses after eight seconds without a refresh. Drafts never reach the
  server. Leases are not audited and are not history.
  """

  import Ecto.Query

  alias Atlas.Orbit
  alias Atlas.Orbit.Access
  alias Atlas.Orbit.Thread
  alias Atlas.Orbit.Viewer
  alias Atlas.Repo
  alias Atlas.Users.User

  @typing_seconds 8

  def typing_seconds, do: @typing_seconds

  def enter(%Thread{id: thread_id}, %User{id: user_id}, connection_id) do
    Repo.insert_all(
      Viewer,
      [%{connection_id: connection_id, thread_id: thread_id, user_id: user_id}],
      conflict_target: [:connection_id],
      on_conflict:
        from(viewer in Viewer, update: [set: [expires_at: fragment("clock_timestamp() + interval '20 seconds'")]])
    )

    Orbit.notify_changed(thread_id)
    :ok
  end

  def renew(%Thread{} = thread, %User{} = user, connection_id) do
    {count, _} =
      Repo.update_all(
        from(viewer in Viewer,
          where: viewer.connection_id == ^connection_id,
          update: [set: [expires_at: fragment("clock_timestamp() + interval '20 seconds'")]]
        ),
        []
      )

    if count == 0, do: enter(thread, user, connection_id), else: :ok
  end

  def typing(thread_id, connection_id, typing?) do
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
    if count > 0, do: Orbit.notify_changed(thread_id)
    :ok
  end

  def leave(thread_id, connection_id) do
    {count, _} = Repo.delete_all(from viewer in Viewer, where: viewer.connection_id == ^connection_id)
    if count > 0, do: Orbit.notify_changed(thread_id)
    :ok
  end

  @doc "Removes expired leases and notifies affected threads."
  def prune do
    {_count, thread_ids} =
      Repo.delete_all(
        from viewer in Viewer,
          where: viewer.expires_at <= fragment("clock_timestamp()"),
          select: viewer.thread_id
      )

    thread_ids |> Enum.uniq() |> Enum.each(&Orbit.notify_changed/1)
    :ok
  end

  defp agent_status(thread) do
    case Orbit.active_run(thread) do
      nil -> if Orbit.agent_configured?(), do: "idle", else: "unconfigured"
      run -> run.status
    end
  end

  @doc """
  `%{revision, people, agent_status}` where people are participants who can currently read
  the thread and hold a live lease, including the caller.
  """
  def snapshot(%Thread{id: thread_id} = thread) do
    thread = Repo.get(Thread, thread_id) || thread
    readers = thread |> Access.audience() |> Map.new(&{&1.id, &1})

    people =
      Repo.all(
        from viewer in Viewer,
          where: viewer.thread_id == ^thread_id and viewer.expires_at > fragment("clock_timestamp()"),
          group_by: viewer.user_id,
          select: {viewer.user_id, fragment("bool_or(coalesce(? > clock_timestamp(), false))", viewer.typing_until)}
      )
      |> Enum.flat_map(fn {user_id, typing?} ->
        case Map.fetch(readers, user_id) do
          {:ok, user} -> [%{id: user.id, name: Orbit.display_name(user), typing: typing?}]
          :error -> []
        end
      end)
      |> Enum.sort_by(&{&1.name, &1.id})

    %{revision: thread.last_seq, people: people, agent_status: agent_status(thread)}
  end
end
