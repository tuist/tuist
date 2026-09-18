defmodule Atlas.Briefs.ItemActions do
  @moduledoc false

  import Ecto.Query

  alias Atlas.Audit
  alias Atlas.Briefs.Brief
  alias Atlas.Briefs.BriefItem
  alias Atlas.Briefs.Suppression
  alias Atlas.Briefs.Workers.RefreshBriefMessage
  alias Atlas.Repo
  alias Atlas.Users
  alias Atlas.Users.User

  @closed_suppression_days 30

  def handle_slack_action(action, item_id, opts \\ []) do
    actor = slack_actor(opts)
    opts = Keyword.put(opts, :actor, actor)

    with %User{} <- actor,
         true <- Users.executive?(actor) do
      case action do
        "claim" -> claim(item_id, actor, opts)
        "acknowledge" -> acknowledge(item_id, actor, opts)
        "useful" -> rate(item_id, "useful", "Rated useful from Slack", actor, opts)
        "not_useful" -> rate_and_suppress(item_id, actor, opts)
        "mute" -> suppress(item_id, "Muted from Slack", 30, actor, opts)
        _action -> {:error, :unsupported_brief_action}
      end
    else
      nil -> {:error, :brief_item_actor_required}
      false -> {:error, :brief_item_executive_required}
    end
    |> action_message(action)
  end

  def claim(item_or_id, actor, opts \\ [])

  def claim(item_or_id, %User{} = actor, opts) do
    update_item(
      item_or_id,
      opts,
      fn item ->
        BriefItem.changeset(item, %{owner_id: actor.id, status: "acknowledged"})
      end,
      "brief_item.claimed",
      actor
    )
  end

  def claim(_item_or_id, _actor, _opts), do: {:error, :brief_item_actor_required}

  def acknowledge(item_or_id, actor \\ nil, opts \\ []) do
    update_item(
      item_or_id,
      opts,
      fn item ->
        BriefItem.changeset(item, %{status: "acknowledged"})
      end,
      "brief_item.acknowledged",
      actor
    )
  end

  def complete(item_or_id, note, actor \\ nil, opts \\ []) do
    case normalize_note(note) do
      nil ->
        {:error, :resolution_note_required}

      note ->
        now = utc_now()

        update_item_with_suppression(
          item_or_id,
          opts,
          fn item ->
            BriefItem.changeset(item, %{
              status: "completed",
              resolved_at: now,
              resolved_by_id: actor && actor.id,
              resolution_note: note
            })
          end,
          "brief_item.completed",
          actor,
          "Completed item cooldown",
          @closed_suppression_days
        )
    end
  end

  def dismiss(item_or_id, reason, actor \\ nil, opts \\ []) do
    now = utc_now()

    update_item_with_suppression(
      item_or_id,
      opts,
      fn item ->
        BriefItem.changeset(item, %{
          status: "dismissed",
          resolved_at: now,
          resolved_by_id: actor && actor.id,
          resolution_note: reason
        })
      end,
      "brief_item.dismissed",
      actor,
      reason || "Dismissed item cooldown",
      @closed_suppression_days
    )
  end

  def rate(item_or_id, usefulness, reason, actor \\ nil, opts \\ []) when usefulness in ["useful", "not_useful"] do
    update_item(
      item_or_id,
      opts,
      fn item ->
        BriefItem.changeset(item, %{
          usefulness: usefulness,
          usefulness_reason: reason,
          usefulness_at: utc_now(),
          usefulness_by_id: actor && actor.id
        })
      end,
      "brief_item.rated",
      actor
    )
  end

  def suppress(item_or_id, reason, days, actor \\ nil, opts \\ []) when is_integer(days) and days > 0 do
    update_item_with_suppression(
      item_or_id,
      opts,
      fn item -> BriefItem.changeset(item, %{status: "suppressed"}) end,
      "brief_item.suppressed",
      actor,
      reason,
      days
    )
  end

  defp rate_and_suppress(item_id, actor, opts) do
    update_item_with_suppression(
      item_id,
      opts,
      fn item ->
        BriefItem.changeset(item, %{
          status: "suppressed",
          usefulness: "not_useful",
          usefulness_reason: "Rated not useful from Slack",
          usefulness_at: utc_now(),
          usefulness_by_id: actor.id
        })
      end,
      ["brief_item.rated", "brief_item.suppressed"],
      actor,
      "Not useful",
      14
    )
  end

  defp update_item(item_or_id, opts, changeset_fun, audit_action, actor) do
    Repo.transaction(fn ->
      item = lock_item(item_or_id)

      case item do
        nil -> Repo.rollback(:not_found)
        item -> item |> changeset_fun.() |> Repo.update!()
      end
    end)
    |> finish_update(audit_action, actor, opts)
  end

  defp update_item_with_suppression(
         item_or_id,
         opts,
         changeset_fun,
         audit_actions,
         actor,
         suppression_reason,
         suppression_days
       ) do
    Repo.transaction(fn ->
      item = lock_item(item_or_id)

      case item do
        nil ->
          Repo.rollback(:not_found)

        item ->
          item = item |> changeset_fun.() |> Repo.update!()

          case upsert_suppression(item, suppression_reason, suppression_days, actor) do
            {:ok, _suppression} -> item
            {:error, reason} -> Repo.rollback(reason)
          end
      end
    end)
    |> finish_update(audit_actions, actor, opts)
  end

  defp finish_update(result, audit_actions, actor, opts) do
    case result do
      {:ok, item} ->
        audit_actions
        |> List.wrap()
        |> Enum.each(&audit_item(&1, item, actor, opts))

        enqueue_refresh(item.brief_id)
        {:ok, item}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp lock_item(%BriefItem{id: id}), do: lock_item(id)

  defp lock_item(id) when is_binary(id) do
    BriefItem
    |> where([item], item.id == ^id)
    |> lock("FOR UPDATE")
    |> Repo.one()
  end

  defp upsert_suppression(item, reason, days, actor) do
    suppressed_until = DateTime.add(utc_now(), days, :day)
    subscription_id = brief_subscription_id(item.brief_id)

    %Suppression{}
    |> Suppression.changeset(%{
      brief_subscription_id: subscription_id,
      domain: item.domain,
      fingerprint: item.fingerprint,
      reason: reason || "Suppressed",
      suppressed_until: suppressed_until,
      severity: item.severity,
      created_by_id: actor && actor.id,
      source_brief_item_id: item.id
    })
    |> Repo.insert(
      on_conflict:
        {:replace, [:reason, :suppressed_until, :severity, :created_by_id, :source_brief_item_id, :updated_at]},
      conflict_target: [:brief_subscription_id, :domain, :fingerprint],
      returning: true
    )
  end

  defp brief_subscription_id(brief_id) do
    Brief
    |> where([brief], brief.id == ^brief_id)
    |> select([brief], brief.brief_subscription_id)
    |> Repo.one!()
  end

  defp slack_actor(opts) do
    case Keyword.get(opts, :actor_email) do
      email when is_binary(email) and email != "" -> Users.get_user_by_email(email)
      _email -> nil
    end
  end

  defp audit_item(action, item, actor, opts) do
    Audit.record(
      action,
      %{
        target_type: "brief_item",
        target_id: item.id,
        target_label: item.title,
        metadata: %{
          "brief_id" => item.brief_id,
          "domain" => item.domain,
          "status" => item.status,
          "owner_id" => item.owner_id,
          "usefulness" => item.usefulness
        }
      },
      Keyword.put(opts, :actor, actor)
    )
  end

  # Coalesces a burst of actions on the same brief into one Slack rewrite, but
  # only against jobs that have not started yet. A job already executing may
  # have read the items before this change landed, so it cannot stand in for
  # this refresh.
  defp enqueue_refresh(brief_id) do
    %{"brief_id" => brief_id}
    |> RefreshBriefMessage.new(
      schedule_in: 2,
      unique: [period: 30, fields: [:worker, :args], states: [:available, :scheduled]]
    )
    |> Oban.insert()
  end

  defp action_message({:ok, item}, "claim"), do: {:ok, %{message: "You now own: #{item.title}"}}
  defp action_message({:ok, item}, "acknowledge"), do: {:ok, %{message: "Acknowledged: #{item.title}"}}
  defp action_message({:ok, item}, "useful"), do: {:ok, %{message: "Marked useful: #{item.title}"}}

  defp action_message({:ok, item}, "not_useful"),
    do: {:ok, %{message: "Marked not useful and muted for 14 days: #{item.title}"}}

  defp action_message({:ok, item}, "mute"), do: {:ok, %{message: "Muted for 30 days: #{item.title}"}}
  defp action_message({:error, reason}, _action), do: {:error, reason}

  defp normalize_note(note) when is_binary(note) do
    case String.trim(note) do
      "" -> nil
      note -> note
    end
  end

  defp normalize_note(_note), do: nil

  defp utc_now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
