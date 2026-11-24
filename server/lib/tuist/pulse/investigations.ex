defmodule Tuist.Pulse.Investigations do
  @moduledoc """
  Investigation requests for mirrored symptoms at board or page tier.
  Triggers record the work to investigate, but do not generate briefs or
  mitigation steps. Those belong to the agent; no agent execution is wired
  here yet. Existing briefs and step feedback remain readable.
  See `symptoms/README.md`, "Investigations".

  The evaluator reads each trigger back as an `investigation` row (`state_rows/1`),
  which is why the name stays.

  ## Triggers

  `on_applied/2` runs inside the mirror's transaction for the revisions that
  became a symptom's latest (`Tuist.Pulse.Symptoms.sync/1`), each decided by its
  own fields. A **root** symptom (`root.root_symptom_id == id`) that is open
  gets an investigation request when the revision:

  - opened it at page tier (`opened_page`), escalated it to page
    (`escalated_page`) or reopened it at board or page tier (`reopened`);
  - ranks it first or second on the evaluator's board push (`board.rank`,
    `board_top_two`, once per symptom and board date);

  and a Pulse-authorized person can ask for one at any time (`request_brief/3`,
  on the symptom's root). Any other symptom opened, reopened or escalated at
  board or page tier gets one request (the legacy `brief` trigger). Within
  one sync a symptom gets at most one request.

  Every trigger is one row, idempotent per `request_id`:
  `uuid5(symptom_id, "investigate:<seq>")` for a log revision,
  `"board:<date>"` for a board push and `"person:<change_seq>"` for a person,
  so a replayed revision never writes a second request.
  Every write draws its `change_seq` (and with it the
  state lock) before reading what exists, so a person's request and a sync
  never act on a stale read. A symptom merged into a root joins the root's
  latest row through `member_symptom_ids`.
  """

  import Ecto.Query

  alias Tuist.Pulse
  alias Tuist.Pulse.Investigations.Brief
  alias Tuist.Pulse.Investigations.BriefStep
  alias Tuist.Pulse.Investigations.Investigation
  alias Tuist.Pulse.Symptom
  alias Tuist.Pulse.Symptoms
  alias Tuist.Repo
  alias Uniq.UUID

  @step_statuses %{"proposed" => :proposed, "taken" => :taken, "helped" => :helped, "did_not_help" => :did_not_help}

  def request_id(symptom_id, trigger_seq), do: UUID.uuid5(symptom_id, "investigate:#{trigger_seq}")

  ## Triggers

  @doc """
  Records investigation requests for `revisions` (parsed log revisions that became their
  symptom's latest when applied, in `seq` order). Call inside the mirror's
  transaction.
  """
  def on_applied(_account, []), do: :ok

  def on_applied(account, revisions) do
    _briefed =
      Enum.reduce(revisions, MapSet.new(), fn revision, briefed ->
        case Repo.get(Symptom, revision.id) do
          %Symptom{} = stored -> consider(account, struct(stored, revision.fields), revision.document, briefed)
          nil -> briefed
        end
      end)

    :ok
  end

  defp consider(account, %Symptom{state: :merged, merged_into: root_id} = symptom, _document, briefed)
       when is_binary(root_id) do
    join_root(account, root_id, symptom.id)
    briefed
  end

  defp consider(account, %Symptom{state: :open, tier: tier} = symptom, document, briefed) when tier in [:board, :page] do
    cond do
      MapSet.member?(briefed, symptom.id) ->
        briefed

      kind = trigger_kind(symptom) ->
        trigger(account, symptom, kind, symptom.seq, request_id(symptom.id, symptom.seq))
        MapSet.put(briefed, symptom.id)

      date = top_two_date(symptom, document) ->
        trigger(account, symptom, :board_top_two, symptom.seq, UUID.uuid5(symptom.id, "board:#{date}"))
        MapSet.put(briefed, symptom.id)

      symptom.transition in [:opened, :reopened, :escalated] ->
        brief_once(account, symptom)
        MapSet.put(briefed, symptom.id)

      true ->
        briefed
    end
  end

  defp consider(_account, _symptom, _document, briefed), do: briefed

  defp trigger_kind(symptom) do
    if root?(symptom) do
      case {symptom.transition, symptom.tier} do
        {:opened, :page} -> :opened_page
        {:escalated, :page} -> :escalated_page
        {:reopened, _tier} -> :reopened
        _ -> nil
      end
    end
  end

  defp root?(%Symptom{id: id, root: %{"root_symptom_id" => root_id}}) when is_binary(root_id),
    do: Ecto.UUID.cast(root_id) == {:ok, id}

  defp root?(_symptom), do: false

  # The evaluator's board push (`board: {date, rank, ...}` on an `annotated`
  # revision) ranks open board roots; ranks 1 and 2 get a brief once per push.
  defp top_two_date(symptom, %{"board" => %{"rank" => rank, "date" => date}})
       when rank in [1, 2] and is_binary(date) and byte_size(date) <= 32 do
    if root?(symptom), do: date
  end

  defp top_two_date(_symptom, _document), do: nil

  @doc """
  A person requests investigation of the symptom's root (the symptom itself
  when it has no mirrored root). Does not generate a brief.
  Returns `{:ok, investigation}`,
  `{:error, :forbidden}` or `{:error, :not_found}`.
  """
  def request_brief(user, account, symptom_id) do
    with true <- Pulse.authorized?(user, account),
         {:ok, id} <- Ecto.UUID.cast(symptom_id),
         %Symptom{} = symptom <- Repo.get_by(Symptom, id: id, account_id: account.id) do
      root = root_of(symptom, account)

      Repo.transaction(fn ->
        change_seq = Symptoms.draw_change_seq()

        create!(account, root, change_seq, %{
          trigger: :person,
          trigger_seq: change_seq,
          request_id: UUID.uuid5(root.id, "person:#{change_seq}"),
          requested_by_id: user.id
        })
      end)
    else
      false -> {:error, :forbidden}
      _ -> {:error, :not_found}
    end
  end

  defp root_of(symptom, account) do
    with false <- root?(symptom),
         %{"root_symptom_id" => root_id} <- symptom.root || %{},
         {:ok, root_id} <- Ecto.UUID.cast(root_id),
         %Symptom{} = root <- Repo.get_by(Symptom, id: root_id, account_id: account.id) do
      root
    else
      _ -> symptom
    end
  end

  defp trigger(account, symptom, kind, trigger_seq, request_id) do
    change_seq = Symptoms.draw_change_seq()

    if !Repo.exists?(from(i in Investigation, where: i.request_id == ^request_id)) do
      create!(account, symptom, change_seq, %{trigger: kind, trigger_seq: trigger_seq, request_id: request_id})
    end

    :ok
  end

  defp brief_once(account, symptom) do
    change_seq = Symptoms.draw_change_seq()

    if !Repo.exists?(from(i in Investigation, where: i.symptom_id == ^symptom.id)) do
      create!(account, symptom, change_seq, %{
        trigger: :brief,
        trigger_seq: symptom.seq,
        request_id: UUID.uuid5(symptom.id, "brief:#{symptom.seq}")
      })
    end

    :ok
  end

  # Record the trigger in the caller's transaction; the agent owns its content.
  defp create!(account, symptom, change_seq, attrs) do
    members =
      case symptom.root do
        %{"member_symptom_ids" => ids} when is_list(ids) ->
          for id <- ids, {:ok, id} <- [Ecto.UUID.cast(id)], id != symptom.id, do: id

        _ ->
          []
      end

    Repo.insert!(
      struct(
        Investigation,
        Map.merge(attrs, %{
          account_id: account.id,
          symptom_id: symptom.id,
          member_symptom_ids: members,
          change_seq: change_seq
        })
      )
    )
  end

  defp join_root(account, root_id, member_id) do
    change_seq = Symptoms.draw_change_seq()

    investigation =
      Repo.one(
        from(i in Investigation,
          where: i.account_id == ^account.id and i.symptom_id == ^root_id,
          order_by: [desc: i.inserted_at, desc: i.id],
          limit: 1
        )
      )

    if investigation && member_id not in investigation.member_symptom_ids do
      Repo.update!(
        Ecto.Changeset.change(investigation,
          member_symptom_ids: investigation.member_symptom_ids ++ [member_id],
          change_seq: change_seq
        )
      )
    end

    :ok
  end

  ## Reads and people

  @doc """
  The symptom's latest investigation (its own, or the one it joined) and the
  latest brief of the briefed symptom with its steps.
  """
  def get(user, account, symptom_id) do
    with true <- Pulse.authorized?(user, account),
         {:ok, id} <- Ecto.UUID.cast(symptom_id) do
      investigation =
        Repo.one(
          from(i in Investigation,
            where: i.account_id == ^account.id and (i.symptom_id == ^id or ^id in i.member_symptom_ids),
            order_by: [desc: i.inserted_at, desc: i.id],
            limit: 1
          )
        )

      brief_symptom = if investigation, do: investigation.symptom_id, else: id

      brief =
        Repo.one(
          from(b in Brief,
            where: b.account_id == ^account.id and b.symptom_id == ^brief_symptom,
            order_by: [desc: b.version],
            limit: 1,
            preload: [steps: ^from(s in BriefStep, order_by: s.position)]
          )
        )

      {:ok, %{investigation: investigation, brief: brief}}
    else
      false -> {:error, :forbidden}
      _ -> {:error, :not_found}
    end
  end

  @doc """
  Sets a brief step's status (`proposed`, `taken`, `helped`, `did_not_help`).
  Only people Pulse authorizes for the account may; the change reaches the
  evaluator through the investigation's `change_seq`.
  """
  def set_step_status(user, account, step_id, status) do
    with true <- Pulse.authorized?(user, account),
         {:ok, status} <- Map.fetch(@step_statuses, status),
         {:ok, id} <- Ecto.UUID.cast(step_id),
         %BriefStep{} = step <- Repo.get_by(BriefStep, id: id, account_id: account.id) do
      {:ok, _} =
        Repo.transaction(fn ->
          change_seq = Symptoms.draw_change_seq()
          now = DateTime.truncate(DateTime.utc_now(), :second)
          Repo.update!(Ecto.Changeset.change(step, status: status, status_by_id: user.id, status_changed_at: now))
          brief = Repo.get!(Brief, step.brief_id)

          Repo.update_all(from(i in Investigation, where: i.id == ^brief.investigation_id),
            set: [change_seq: change_seq, updated_at: now]
          )
        end)

      :ok
    else
      false -> {:error, :forbidden}
      :error -> {:error, :invalid_params}
      _ -> {:error, :not_found}
    end
  end

  @doc """
  Investigations as the evaluator reads them back: symptom, members, trigger,
  the latest brief's ID and version, the steps people marked (any status but
  `proposed`), and `reverted`: true when a person marked a step of any of the
  symptom's briefs `taken`, `helped` or `did_not_help` (the evaluator's
  `revert_after_brief`). Every step is a mitigate-now step.
  """
  def state_rows([]), do: []

  def state_rows(investigations) do
    symptom_ids = investigations |> Enum.map(& &1.symptom_id) |> Enum.uniq()

    briefs =
      from(b in Brief,
        where: b.symptom_id in ^symptom_ids,
        distinct: b.symptom_id,
        order_by: [asc: b.symptom_id, desc: b.version]
      )
      |> Repo.all()
      |> Map.new(&{&1.symptom_id, &1})

    brief_ids = briefs |> Map.values() |> Enum.map(& &1.id)

    steps =
      from(s in BriefStep, where: s.brief_id in ^brief_ids and s.status != :proposed, order_by: s.position)
      |> Repo.all()
      |> Enum.group_by(& &1.brief_id)

    reverted = reverted_symptom_ids(symptom_ids)

    for investigation <- investigations do
      brief = Map.get(briefs, investigation.symptom_id)

      %{
        "symptom_id" => investigation.symptom_id,
        "member_symptom_ids" => investigation.member_symptom_ids,
        "trigger" => Atom.to_string(investigation.trigger),
        "brief_id" => brief && brief.id,
        "brief_revision" => brief && brief.version,
        "steps_taken" =>
          for step <- Map.get(steps, brief && brief.id, []) do
            %{"step_id" => step.id, "kind" => Atom.to_string(step.kind), "status" => Atom.to_string(step.status)}
          end,
        "reverted" => MapSet.member?(reverted, investigation.symptom_id),
        "change_seq" => investigation.change_seq
      }
    end
  end

  # Any brief version counts: a newer brief must not hide a revert people
  # already made from an older one.
  defp reverted_symptom_ids(symptom_ids) do
    from(s in BriefStep,
      join: b in Brief,
      on: b.id == s.brief_id,
      where: b.symptom_id in ^symptom_ids and s.status != :proposed,
      distinct: true,
      select: b.symptom_id
    )
    |> Repo.all()
    |> MapSet.new()
  end
end
