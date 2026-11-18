defmodule Tuist.Halls do
  @moduledoc """
  Long-lived conversations between people in an organization, with no agent
  involved. A hall is named and every member of the organization can read and
  write in it; a direct conversation belongs to the two to eight members who
  started it. Neither ends: each person keeps a read position instead.

  Threads stay the agent's bounded conversations. Halls live in their own
  tables because threads are private to an owner whose AI subscription runs
  them, while a hall has no owner.
  """
  import Ecto.Query

  alias Tuist.Accounts
  alias Tuist.Accounts.Account
  alias Tuist.Accounts.Organization
  alias Tuist.Accounts.User
  alias Tuist.FeatureFlags
  alias Tuist.Halls.Hall
  alias Tuist.Halls.Member
  alias Tuist.Halls.Message
  alias Tuist.Halls.Presence
  alias Tuist.Repo

  @page 50
  @direct_members 2..8
  @name ~r/\A[a-z0-9][a-z0-9_-]{0,63}\z/

  # Halls need the same `guild` flags as threads, but any member of the
  # organization may use them, not only its admins.
  def authorize(%User{active: true, disabled_at: nil} = user, %Account{organization_id: id} = account)
      when not is_nil(id) do
    with true <- FeatureFlags.guild_enabled?(user) and FeatureFlags.organization_guild_enabled?(account),
         {:ok, %Organization{} = organization} <- Accounts.get_organization_by_id(id),
         true <- Accounts.belongs_to_organization?(user, organization) do
      :ok
    else
      _ -> {:error, :forbidden}
    end
  end

  def authorize(_, _), do: {:error, :forbidden}

  @doc "The account's halls by name, and the person's direct conversations by latest activity."
  def list(user, account) do
    with :ok <- authorize(user, account) do
      # Two queries on their own indexes: the organization's halls by name
      # (the partial unique name index), and the person's direct conversations
      # through their memberships, so nobody else's DMs are read.
      halls =
        Repo.all(
          from h in Hall,
            left_join: me in Member,
            on: me.hall_id == h.id and me.user_id == ^user.id,
            left_join: m in Message,
            on: m.hall_id == h.id and m.position == h.last_position,
            where: h.account_id == ^account.id and h.kind == :hall,
            order_by: h.name,
            limit: 1000,
            select: {h, coalesce(me.last_read_position, 0), m}
        )

      directs =
        Repo.all(
          from me in Member,
            join: h in Hall,
            on: h.id == me.hall_id,
            left_join: m in Message,
            on: m.hall_id == h.id and m.position == h.last_position,
            where: me.user_id == ^user.id and h.account_id == ^account.id and h.kind == :direct,
            order_by: [desc: h.updated_at, desc: h.id],
            limit: 200,
            select: {h, me.last_read_position, m}
        )

      people = people_by_id(halls ++ directs, Presence.online(account))

      present =
        &Enum.map(&1, fn {hall, read, last} ->
          hall
          |> summary(user, read, people)
          |> Map.put(:last_message, last && serialize_message(last, user, people))
        end)

      {:ok, %{halls: present.(halls), directs: present.(directs)}}
    end
  end

  @doc "Members of the organization a person can start a direct conversation with."
  def people(user, account) do
    with :ok <- authorize(user, account) do
      {:ok, organization} = Accounts.get_organization_by_id(account.organization_id)
      online = Presence.online(account)

      members =
        organization
        |> Accounts.get_organization_members()
        # Only people `direct/3` accepts.
        |> Enum.reject(&(&1.id == user.id or not &1.active or not is_nil(&1.disabled_at)))
        |> Enum.map(&person(&1, online))

      {:ok, members}
    end
  end

  def create(user, account, attrs) do
    with :ok <- authorize(user, account),
         {:ok, request_id} <- uuid(attrs["request_id"]),
         {:ok, name} <- name(attrs["name"]),
         {:ok, topic} <- topic(attrs["topic"]) do
      fn ->
        now = now()

        row = %{
          id: Ecto.UUID.generate(),
          account_id: account.id,
          kind: :hall,
          name: name,
          topic: topic,
          created_by_id: user.id,
          request_id: request_id,
          inserted_at: now,
          updated_at: now
        }

        # A retry racing the original on another replica waits on the request
        # index and then inserts nothing, so both read the same hall back.
        insert_once!(row, [:account_id, :request_id])

        case Repo.get_by!(Hall, account_id: account.id, request_id: request_id) do
          %Hall{kind: :hall, name: ^name} = hall -> hall
          %Hall{} -> Repo.rollback(:request_conflict)
        end
      end
      |> transact()
      |> then(fn result -> with {:ok, hall} <- result, do: get(user, account, hall.id) end)
    end
  end

  # Inserts `row` unless it conflicts on `target`; true when it did. Another
  # hall's name is the only other conflict, reported as `:name_taken`.
  defp insert_once!(row, target) do
    {count, _} = Repo.insert_all(Hall, [row], on_conflict: :nothing, conflict_target: target)
    count == 1
  rescue
    error in Postgrex.Error ->
      case error.postgres do
        %{code: :unique_violation, constraint: "halls_account_id_name_index"} -> Repo.rollback(:name_taken)
        _ -> reraise error, __STACKTRACE__
      end
  end

  @doc """
  The direct conversation between the person and `user_ids`, started if it
  doesn't exist yet. The same people always reach the same conversation.
  """
  def direct(user, account, attrs) do
    with :ok <- authorize(user, account),
         {:ok, _request_id} <- uuid(attrs["request_id"]),
         {:ok, ids} <- direct_members(user, attrs["user_ids"]),
         :ok <- members_of(account, ids) do
      key = Enum.join(ids, ",")

      fn ->
        now = now()
        id = Ecto.UUID.generate()

        # The people, not the request, identify a direct conversation: the
        # partial direct-key index makes a concurrent start insert nothing and
        # read the first one back, members included, once it commits. Its own
        # request ID would only collide with another conversation's.
        row = %{
          id: id,
          account_id: account.id,
          kind: :direct,
          direct_key: key,
          created_by_id: user.id,
          request_id: Ecto.UUID.generate(),
          inserted_at: now,
          updated_at: now
        }

        if insert_once!(row, {:unsafe_fragment, "(account_id, direct_key) WHERE kind = 'direct'"}) do
          Repo.insert_all(Member, Enum.map(ids, &%{hall_id: id, user_id: &1, inserted_at: now, updated_at: now}))
        end

        Repo.get_by!(Hall, account_id: account.id, kind: :direct, direct_key: key)
      end
      |> transact()
      |> then(fn result -> with {:ok, hall} <- result, do: get(user, account, hall.id) end)
    end
  end

  def get(user, account, id, opts \\ []) do
    with :ok <- authorize(user, account),
         {:ok, hall, read} <- visible(user, account, id),
         {:ok, before} <- before_position(Keyword.get(opts, :before)) do
      query = from m in Message, where: m.hall_id == ^hall.id, order_by: [desc: m.position], limit: ^(@page + 1)
      query = if before, do: from(m in query, where: m.position < ^before), else: query
      rows = Repo.all(query)
      messages = rows |> Enum.take(@page) |> Enum.reverse()
      has_more = length(rows) > @page
      people = people_by_id([{hall, read, nil} | Enum.map(messages, &{nil, nil, &1})], Presence.online(account))

      {:ok,
       hall
       |> summary(user, read, people)
       |> Map.merge(%{
         messages: Enum.map(messages, &serialize_message(&1, user, people)),
         has_more: has_more,
         next_before: if(has_more, do: List.first(messages).position)
       })}
    end
  end

  def message(user, account, id, attrs) do
    with :ok <- authorize(user, account),
         {:ok, hall, _read} <- visible(user, account, id),
         {:ok, request_id} <- uuid(attrs["request_id"]),
         {:ok, body} <- content(attrs["content"]) do
      fn ->
        hall = Repo.one!(from h in Hall, where: h.id == ^hall.id, lock: "FOR UPDATE")

        case Repo.get_by(Message, hall_id: hall.id, request_id: request_id) do
          # Only the author's own retry replays; anyone else's reuse conflicts.
          %Message{author_id: author, body: ^body} when author == user.id ->
            :ok

          %Message{} ->
            Repo.rollback(:request_conflict)

          nil ->
            position = hall.last_position + 1

            Repo.insert!(%Message{
              hall_id: hall.id,
              author_id: user.id,
              request_id: request_id,
              position: position,
              body: body
            })

            Repo.update!(Ecto.Changeset.change(hall, last_position: position, updated_at: now()))
            # Writing means having read everything up to it.
            mark!(hall.id, user.id, position)
        end
      end
      |> transact()
      |> then(fn result -> with {:ok, _} <- result, do: get(user, account, hall.id) end)
    end
  end

  @doc "Moves the person's read position forward; it never moves back."
  def read(user, account, id, position) do
    with :ok <- authorize(user, account),
         {:ok, hall, _read} <- visible(user, account, id),
         {:ok, position} <- before_position(position) do
      mark!(hall.id, user.id, min(position, hall.last_position))
      {:ok, %{read_position: Repo.get_by!(Member, hall_id: hall.id, user_id: user.id).last_read_position}}
    end
  end

  defp visible(user, account, id) do
    with {:ok, id} <- uuid(id),
         %Hall{} = hall <- Repo.get_by(Hall, id: id, account_id: account.id) do
      member = Repo.get_by(Member, hall_id: hall.id, user_id: user.id)

      cond do
        hall.kind == :hall -> {:ok, hall, (member && member.last_read_position) || 0}
        member -> {:ok, hall, member.last_read_position}
        true -> {:error, :not_found}
      end
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end

  defp mark!(hall_id, user_id, position) do
    now = now()

    Repo.insert_all(
      Member,
      [%{hall_id: hall_id, user_id: user_id, last_read_position: position, inserted_at: now, updated_at: now}],
      conflict_target: [:hall_id, :user_id],
      on_conflict:
        from(m in Member,
          update: [set: [last_read_position: fragment("GREATEST(?, EXCLUDED.last_read_position)", m.last_read_position)]]
        )
    )
  end

  defp summary(hall, user, read, people) do
    members =
      case hall.kind do
        :direct ->
          hall.direct_key
          |> String.split(",")
          |> Enum.map(&String.to_integer/1)
          |> Enum.reject(&(&1 == user.id))
          |> Enum.map(&(people[&1] || %{id: &1, handle: nil, online: false}))

        :hall ->
          []
      end

    %{
      id: hall.id,
      kind: hall.kind,
      name: hall.name,
      topic: hall.topic,
      members: members,
      last_position: hall.last_position,
      read_position: read,
      unread: max(hall.last_position - read, 0),
      updated_at: hall.updated_at
    }
  end

  defp serialize_message(message, user, people) do
    %{
      id: message.id,
      position: message.position,
      body: message.body,
      author: message.author_id && (people[message.author_id] || %{id: message.author_id, handle: nil, online: false}),
      mine: message.author_id == user.id,
      inserted_at: message.inserted_at
    }
  end

  # Everyone the rows mention, loaded at once: direct members and authors.
  defp people_by_id(rows, online) do
    ids =
      rows
      |> Enum.flat_map(fn {hall, _read, message} ->
        direct =
          if hall && hall.kind == :direct,
            do: hall.direct_key |> String.split(",") |> Enum.map(&String.to_integer/1),
            else: []

        if message && message.author_id, do: [message.author_id | direct], else: direct
      end)
      |> Enum.uniq()

    from(u in User, where: u.id in ^ids, preload: :account)
    |> Repo.all()
    |> Map.new(&{&1.id, person(&1, online)})
  end

  # `online`: the person has Tuist Guild open in this organization right now.
  defp person(user, online), do: %{id: user.id, handle: user.account.name, online: MapSet.member?(online, user.id)}

  defp direct_members(user, ids) when is_list(ids) do
    if Enum.all?(ids, &is_integer/1) do
      ids = [user.id | ids] |> Enum.uniq() |> Enum.sort()
      if Enum.count(ids) in @direct_members, do: {:ok, ids}, else: {:error, :invalid_arguments}
    else
      {:error, :invalid_arguments}
    end
  end

  defp direct_members(_, _), do: {:error, :invalid_arguments}

  defp members_of(account, ids) do
    {:ok, organization} = Accounts.get_organization_by_id(account.organization_id)
    users = Repo.all(from u in User, where: u.id in ^ids and u.active == true and is_nil(u.disabled_at))

    if length(users) == length(ids) and Enum.all?(users, &Accounts.belongs_to_organization?(&1, organization)),
      do: :ok,
      else: {:error, :invalid_arguments}
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
      "" -> {:ok, nil}
      topic -> if String.length(topic) <= 250, do: {:ok, topic}, else: {:error, :invalid_arguments}
    end
  end

  defp topic(_), do: {:error, :invalid_arguments}

  defp transact(fun), do: Repo.transaction(fun, log: false)

  defp now do
    DateTime.truncate(DateTime.utc_now(), :second)
  end

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
