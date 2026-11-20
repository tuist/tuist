defmodule LuftServer.Lounges do
  @moduledoc "Long-lived public lounges and private direct conversations, scoped by Tuist."
  import Ecto.Query

  alias LuftServer.Lounges.Lounge
  alias LuftServer.Lounges.Member
  alias LuftServer.Lounges.Message
  alias LuftServer.Lounges.Presence
  alias LuftServer.Repo
  alias LuftServer.Tuist.Scope

  @page 50
  @direct_members 2..8
  @name ~r/\A[a-z0-9][a-z0-9_-]{0,63}\z/

  # Scope.load/2 authoritatively checks identity, membership and feature flags.
  # A personal account can have directs, but never public organization lounges.
  def authorize(%Scope{}), do: :ok

  def list(%Scope{} = scope) do
    lounges =
      if scope.organization_id do
        Repo.all(
          from l in Lounge,
            left_join: me in Member,
            on: me.lounge_id == l.id and me.user_id == ^scope.user_id,
            left_join: m in Message,
            on: m.lounge_id == l.id and m.position == l.last_position,
            where: l.account_id == ^scope.account_id and l.kind == :lounge,
            order_by: l.name,
            limit: 1000,
            select: {l, coalesce(me.last_read_position, 0), m}
        )
      else
        []
      end

    directs =
      Repo.all(
        from me in Member,
          join: l in Lounge,
          on: l.id == me.lounge_id,
          left_join: m in Message,
          on: m.lounge_id == l.id and m.position == l.last_position,
          where:
            me.user_id == ^scope.user_id and l.account_id == ^scope.account_id and
              l.kind == :direct,
          order_by: [desc: l.updated_at, desc: l.id],
          limit: 200,
          select: {l, me.last_read_position, m}
      )

    people = people_by_id(scope)

    present =
      &Enum.map(&1, fn {lounge, read, last} ->
        lounge
        |> summary(scope, read, people)
        |> Map.put(:last_message, last && serialize_message(last, scope, people))
      end)

    {:ok, %{lounges: present.(lounges), directs: present.(directs)}}
  end

  def people(%Scope{} = scope) do
    online = Presence.online(scope)

    {:ok,
     scope.people
     |> Enum.filter(&(&1.active and &1.id != scope.user_id))
     |> Enum.map(&person(&1, online))}
  end

  def create(%Scope{} = scope, attrs) do
    with :ok <- public_scope(scope),
         {:ok, request_id} <- uuid(attrs["request_id"]),
         {:ok, name} <- name(attrs["name"]),
         {:ok, topic} <- topic(attrs["topic"]),
         {:ok, invited} <- invitees(scope, Map.get(attrs, "user_ids", [])) do
      fn ->
        now = now()

        row = %{
          id: Ecto.UUID.generate(),
          account_id: scope.account_id,
          kind: :lounge,
          name: name,
          topic: topic,
          created_by_id: scope.user_id,
          request_id: request_id,
          inserted_at: now,
          updated_at: now
        }

        # A retry conflicts on both the request and partial name indexes.
        # PostgreSQL may encounter either index first, so suppress both and
        # distinguish a replay from a taken name using the committed request.
        insert_once!(row, nil)

        case Repo.get_by(Lounge, account_id: scope.account_id, request_id: request_id) do
          %Lounge{kind: :lounge, name: ^name, topic: ^topic, created_by_id: author} = lounge
          when author == scope.user_id ->
            join!(lounge.id, invited)
            lounge

          %Lounge{} ->
            Repo.rollback(:request_conflict)

          nil ->
            Repo.rollback(:name_taken)
        end
      end
      |> transact()
      |> then(fn result -> with {:ok, lounge} <- result, do: get(scope, lounge.id) end)
    end
  end

  def direct(%Scope{} = scope, attrs) do
    with {:ok, _request_id} <- uuid(attrs["request_id"]),
         {:ok, ids} <- direct_members(scope, attrs["user_ids"]),
         :ok <- members_of(scope, ids) do
      key = Enum.join(ids, ",")

      fn ->
        now = now()
        id = Ecto.UUID.generate()

        row = %{
          id: id,
          account_id: scope.account_id,
          kind: :direct,
          direct_key: key,
          created_by_id: scope.user_id,
          request_id: Ecto.UUID.generate(),
          inserted_at: now,
          updated_at: now
        }

        # The people, not a caller's request, identify a direct conversation.
        if insert_once!(row, {:unsafe_fragment, "(account_id, direct_key) WHERE kind = 'direct'"}) do
          Repo.insert_all(
            Member,
            Enum.map(ids, &%{lounge_id: id, user_id: &1, inserted_at: now, updated_at: now})
          )
        end

        Repo.get_by!(Lounge, account_id: scope.account_id, kind: :direct, direct_key: key)
      end
      |> transact()
      |> then(fn result -> with {:ok, lounge} <- result, do: get(scope, lounge.id) end)
    end
  end

  def invite(%Scope{} = scope, id, attrs) do
    with {:ok, %Lounge{kind: :lounge} = lounge, _read} <- visible(scope, id),
         {:ok, [_ | _] = ids} <- invitees(scope, attrs["user_ids"]) do
      join!(lounge.id, ids)
      get(scope, lounge.id)
    else
      {:ok, _lounge, _read} -> {:error, :invalid_arguments}
      {:ok, []} -> {:error, :invalid_arguments}
      error -> error
    end
  end

  def get(%Scope{} = scope, id, opts \\ []) do
    with {:ok, lounge, read} <- visible(scope, id),
         {:ok, before} <- before_position(Keyword.get(opts, :before)) do
      query =
        from m in Message,
          where: m.lounge_id == ^lounge.id,
          order_by: [desc: m.position],
          limit: ^(@page + 1)

      query = if before, do: from(m in query, where: m.position < ^before), else: query
      rows = Repo.all(query)
      messages = rows |> Enum.take(@page) |> Enum.reverse()
      has_more = length(rows) > @page
      people = people_by_id(scope)

      {:ok,
       lounge
       |> summary(scope, read, people)
       |> Map.merge(%{
         member_ids:
           Repo.all(
             from m in Member,
               where: m.lounge_id == ^lounge.id,
               order_by: m.user_id,
               select: m.user_id
           ),
         messages: Enum.map(messages, &serialize_message(&1, scope, people)),
         has_more: has_more,
         next_before: if(has_more, do: List.first(messages).position)
       })}
    end
  end

  def message(%Scope{} = scope, id, attrs) do
    with {:ok, lounge, _read} <- visible(scope, id),
         {:ok, request_id} <- uuid(attrs["request_id"]),
         {:ok, body} <- content(attrs["content"]) do
      fn ->
        lounge = Repo.one!(from l in Lounge, where: l.id == ^lounge.id, lock: "FOR UPDATE")

        case Repo.get_by(Message, lounge_id: lounge.id, request_id: request_id) do
          %Message{author_id: author, body: ^body} when author == scope.user_id ->
            :ok

          %Message{} ->
            Repo.rollback(:request_conflict)

          nil ->
            position = lounge.last_position + 1

            Repo.insert!(%Message{
              lounge_id: lounge.id,
              author_id: scope.user_id,
              request_id: request_id,
              position: position,
              body: body
            })

            Repo.update!(
              Ecto.Changeset.change(lounge, last_position: position, updated_at: now())
            )

            mark!(lounge.id, scope.user_id, position)
        end
      end
      |> transact()
      |> then(fn result -> with {:ok, _} <- result, do: get(scope, lounge.id) end)
    end
  end

  def read(%Scope{} = scope, id, position) do
    with {:ok, lounge, _read} <- visible(scope, id),
         {:ok, position} when not is_nil(position) <- before_position(position) do
      mark!(lounge.id, scope.user_id, min(position, lounge.last_position))

      {:ok,
       %{
         read_position:
           Repo.get_by!(Member, lounge_id: lounge.id, user_id: scope.user_id).last_read_position
       }}
    else
      {:ok, nil} -> {:error, :invalid_arguments}
      error -> error
    end
  end

  defp public_scope(%Scope{organization_id: nil}), do: {:error, :forbidden}
  defp public_scope(%Scope{}), do: :ok

  defp visible(scope, id) do
    with {:ok, id} <- uuid(id),
         %Lounge{} = lounge <- Repo.get_by(Lounge, id: id, account_id: scope.account_id) do
      member = Repo.get_by(Member, lounge_id: lounge.id, user_id: scope.user_id)

      cond do
        lounge.kind == :lounge and not is_nil(scope.organization_id) ->
          {:ok, lounge, (member && member.last_read_position) || 0}

        lounge.kind == :direct and member ->
          {:ok, lounge, member.last_read_position}

        true ->
          {:error, :not_found}
      end
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end

  defp insert_once!(row, target) do
    options =
      if target,
        do: [on_conflict: :nothing, conflict_target: target],
        else: [on_conflict: :nothing]

    {count, _} = Repo.insert_all(Lounge, [row], options)
    count == 1
  rescue
    error in Postgrex.Error ->
      case error.postgres do
        %{code: :unique_violation, constraint: "lounges_account_id_name_index"} ->
          Repo.rollback(:name_taken)

        _ ->
          reraise error, __STACKTRACE__
      end
  end

  defp invitees(scope, ids) when is_list(ids) and length(ids) <= 50 do
    ids = ids |> Enum.uniq() |> Enum.reject(&(&1 == scope.user_id))

    cond do
      not Enum.all?(ids, &is_integer/1) -> {:error, :invalid_arguments}
      ids == [] -> {:ok, []}
      members_of(scope, ids) == :ok -> {:ok, ids}
      true -> {:error, :invalid_arguments}
    end
  end

  defp invitees(_, _), do: {:error, :invalid_arguments}

  defp join!(_lounge_id, []), do: :ok

  defp join!(lounge_id, ids) do
    now = now()

    Repo.insert_all(
      Member,
      Enum.map(ids, &%{lounge_id: lounge_id, user_id: &1, inserted_at: now, updated_at: now}),
      on_conflict: :nothing,
      conflict_target: [:lounge_id, :user_id]
    )

    :ok
  end

  defp mark!(lounge_id, user_id, position) do
    now = now()

    Repo.insert_all(
      Member,
      [
        %{
          lounge_id: lounge_id,
          user_id: user_id,
          last_read_position: position,
          inserted_at: now,
          updated_at: now
        }
      ],
      conflict_target: [:lounge_id, :user_id],
      on_conflict:
        from(m in Member,
          update: [
            set: [
              last_read_position:
                fragment("GREATEST(?, EXCLUDED.last_read_position)", m.last_read_position)
            ]
          ]
        )
    )
  end

  defp summary(lounge, scope, read, people) do
    members =
      if lounge.kind == :direct do
        lounge.direct_key
        |> String.split(",")
        |> Enum.map(&String.to_integer/1)
        |> Enum.reject(&(&1 == scope.user_id))
        |> Enum.map(&(people[&1] || %{id: &1, handle: nil, online: false}))
      else
        []
      end

    %{
      id: lounge.id,
      kind: lounge.kind,
      name: lounge.name,
      topic: lounge.topic,
      members: members,
      last_position: lounge.last_position,
      read_position: read,
      unread: max(lounge.last_position - read, 0),
      updated_at: lounge.updated_at
    }
  end

  defp serialize_message(message, scope, people) do
    %{
      id: message.id,
      position: message.position,
      body: message.body,
      author:
        message.author_id &&
          (people[message.author_id] || %{id: message.author_id, handle: nil, online: false}),
      mine: message.author_id == scope.user_id,
      inserted_at: message.inserted_at
    }
  end

  defp people_by_id(scope) do
    online = Presence.online(scope)
    Map.new(scope.people, &{&1.id, person(&1, online)})
  end

  defp person(user, online),
    do: %{id: user.id, handle: user.handle, online: MapSet.member?(online, user.id)}

  defp direct_members(scope, ids) when is_list(ids) do
    if Enum.all?(ids, &is_integer/1) do
      ids = [scope.user_id | ids] |> Enum.uniq() |> Enum.sort()
      if Enum.count(ids) in @direct_members, do: {:ok, ids}, else: {:error, :invalid_arguments}
    else
      {:error, :invalid_arguments}
    end
  end

  defp direct_members(_, _), do: {:error, :invalid_arguments}

  defp members_of(scope, ids) do
    active = scope.people |> Enum.filter(& &1.active) |> MapSet.new(& &1.id)
    if Enum.all?(ids, &MapSet.member?(active, &1)), do: :ok, else: {:error, :invalid_arguments}
  end

  defp name(value) when is_binary(value) do
    name =
      value
      |> String.trim()
      |> String.trim_leading("#")
      |> String.trim()
      |> String.downcase()
      |> String.replace(~r/\s+/, "-")

    if Regex.match?(@name, name), do: {:ok, name}, else: {:error, :invalid_arguments}
  end

  defp name(_), do: {:error, :invalid_arguments}
  defp topic(nil), do: {:ok, nil}

  defp topic(value) when is_binary(value) do
    case String.trim(value) do
      "" ->
        {:ok, nil}

      topic ->
        if String.length(topic) <= 250, do: {:ok, topic}, else: {:error, :invalid_arguments}
    end
  end

  defp topic(_), do: {:error, :invalid_arguments}
  defp transact(fun), do: Repo.transaction(fun, log: false)
  defp now, do: DateTime.truncate(DateTime.utc_now(), :second)

  defp uuid(value) do
    case Ecto.UUID.cast(value) do
      {:ok, id} -> {:ok, id}
      :error -> {:error, :invalid_arguments}
    end
  end

  defp content(value) when is_binary(value) do
    if String.valid?(value) and String.trim(value) != "" and byte_size(value) <= 16_000,
      do: {:ok, value},
      else: {:error, :invalid_arguments}
  end

  defp content(_), do: {:error, :invalid_arguments}
  defp before_position(nil), do: {:ok, nil}
  defp before_position(value) when is_integer(value) and value > 0, do: {:ok, value}

  defp before_position(value) when is_binary(value) do
    case Integer.parse(value) do
      {number, ""} when number > 0 -> {:ok, number}
      _ -> {:error, :invalid_arguments}
    end
  end

  defp before_position(_), do: {:error, :invalid_arguments}
end
