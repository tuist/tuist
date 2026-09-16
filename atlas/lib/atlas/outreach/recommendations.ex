defmodule Atlas.Outreach.Recommendations do
  @moduledoc """
  Generates, persists, reviews, and delivers guided outreach recommendations.
  """

  import Atlas.Outreach.Util, only: [normalize_optional_text: 1, present?: 1, utc_now: 0, attr: 3, stringify_keys: 1]
  import Ecto.Query

  alias Atlas.Accounts.Account
  alias Atlas.Accounts.Contact
  alias Atlas.Accounts.Event
  alias Atlas.Audit
  alias Atlas.Evidence
  alias Atlas.Outreach
  alias Atlas.Outreach.Agents.RecommendationAgent
  alias Atlas.Outreach.MessageAttempt
  alias Atlas.Outreach.MessageLearning
  alias Atlas.Outreach.Recommendation
  alias Atlas.Outreach.RecommendationNotifier
  alias Atlas.Outreach.Workers.GenerateRecommendation
  alias Atlas.Outreach.Workers.NotifyRecommendation
  alias Atlas.Repo
  alias Atlas.Users

  @agent_name "outreach_recommendation_agent"
  @minimum_confidence Decimal.new("0.70")
  @pending_job_states ~w(available scheduled executing retryable)

  def list(contact_or_id, opts \\ [])

  def list(%Contact{id: contact_id}, opts), do: list(contact_id, opts)

  def list(contact_id, opts) when is_binary(contact_id) do
    statuses = Keyword.get(opts, :statuses)
    limit = Keyword.get(opts, :limit, 20)

    Recommendation
    |> where([recommendation], recommendation.contact_id == ^contact_id)
    |> maybe_filter_statuses(statuses)
    |> order_by([recommendation], desc: recommendation.inserted_at)
    |> limit(^limit)
    |> preload([:contact, :account, :source_event, :reviewed_by])
    |> Repo.all()
  end

  def get(id) when is_binary(id) do
    Recommendation
    |> preload([:account, :source_event, :reviewed_by, contact: :account])
    |> Repo.get(id)
  end

  def get(_id), do: nil

  def current(contact_or_id)

  def current(%Contact{id: contact_id}), do: current(contact_id)

  def current(contact_id) when is_binary(contact_id) do
    Recommendation
    |> where([recommendation], recommendation.contact_id == ^contact_id and recommendation.status == "pending")
    |> order_by([recommendation], desc: recommendation.inserted_at)
    |> limit(1)
    |> preload([:source_event, :reviewed_by])
    |> Repo.one()
  end

  def current(_contact_id), do: nil

  def generate(contact_id) when is_binary(contact_id) do
    case context(contact_id) do
      nil ->
        {:error, :not_found}

      context ->
        case RecommendationAgent.recommend(context) do
          {:ok, result} ->
            case context(contact_id) do
              nil -> {:error, :not_found}
              refreshed_context -> persist_generated(refreshed_context, result)
            end

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  def request_generation(contact_or_id, actor \\ nil, source \\ "dashboard")

  def request_generation(%Contact{id: contact_id}, actor, source), do: request_generation(contact_id, actor, source)

  def request_generation(contact_id, actor, source) when is_binary(contact_id) do
    case Repo.get(Contact, contact_id) do
      nil ->
        {:error, :not_found}

      contact ->
        case enqueue_generation(contact.id, source, force?: true) do
          {:ok, %Oban.Job{conflict?: true} = job} ->
            # Uniqueness collapsed this into a job that is already queued, so no
            # new work was requested and there is nothing to audit as a request.
            {:ok, job}

          {:ok, job} ->
            audit_generation_request(contact, job, source, actor)
            {:ok, job}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  def generation_pending?(contact_or_id)

  def generation_pending?(%Contact{id: contact_id}), do: generation_pending?(contact_id)

  def generation_pending?(contact_id) when is_binary(contact_id) do
    contact_id
    |> generation_jobs()
    |> where([job], job.state in ^@pending_job_states)
    |> Repo.exists?()
  end

  def generation_pending?(_contact_id), do: false

  @doc """
  Reports how the latest generation for a contact ended.

  `:pending` while a job is queued or running, `:completed` once the worker
  finished its run, `:failed` when the job was cancelled or discarded, and
  `:none` when no job is on record. Callers need this to tell "the agent ran and
  found nothing" apart from "the agent never got to run", which the job state
  alone carries once the run is over.
  """
  def generation_status(contact_or_id)

  def generation_status(%Contact{id: contact_id}), do: generation_status(contact_id)

  def generation_status(contact_id) when is_binary(contact_id) do
    if generation_pending?(contact_id) do
      :pending
    else
      latest_generation_outcome(contact_id)
    end
  end

  def generation_status(_contact_id), do: :none

  defp latest_generation_outcome(contact_id) do
    contact_id
    |> generation_jobs()
    |> order_by([job], desc: job.id)
    |> limit(1)
    |> select([job], job.state)
    |> Repo.one()
    |> case do
      nil -> :none
      "completed" -> :completed
      _state -> :failed
    end
  end

  defp generation_jobs(contact_id) do
    worker = inspect(GenerateRecommendation)

    where(
      Oban.Job,
      [job],
      job.worker == ^worker and fragment("?->>'contact_id' = ?", job.args, ^contact_id)
    )
  end

  def complete(recommendation_or_id, actor \\ nil, attrs \\ %{})

  def complete(%Recommendation{id: id}, actor, attrs), do: complete(id, actor, attrs)

  def complete(id, actor, attrs) when is_binary(id) and is_map(attrs) do
    Repo.transaction(fn ->
      recommendation = lock_pending(id)

      with %Recommendation{} <- recommendation,
           {:ok, completion} <- completion_content(recommendation, attrs),
           {:ok, completed} <- update_decision(recommendation, "completed", nil, actor),
           {:ok, completion_contact} <- completion_contact(completed),
           {:ok, event, contact} <-
             record_completion(%{completed | contact: completion_contact}, completion, actor) do
        %{recommendation: completed, event: event, contact: contact}
      else
        nil -> Repo.rollback(:not_found)
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> case do
      {:ok, result} ->
        audit_decision("outreach.recommendation_completed", result.recommendation, actor)
        enqueue_after_completion(result.recommendation)
        {:ok, result}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def dismiss(recommendation_or_id, reason \\ nil, actor \\ nil)

  def dismiss(%Recommendation{id: id}, reason, actor), do: dismiss(id, reason, actor)

  def dismiss(id, reason, actor) when is_binary(id) do
    case get(id) do
      nil ->
        {:error, :not_found}

      recommendation ->
        recommendation
        |> update_decision("dismissed", normalize_optional_text(reason), actor)
        |> tap(fn
          {:ok, dismissed} -> audit_decision("outreach.recommendation_dismissed", dismissed, actor)
          _result -> :ok
        end)
    end
  end

  def regenerate(recommendation_or_id, actor \\ nil, source \\ "manual")

  def regenerate(%Recommendation{id: id}, actor, source), do: regenerate(id, actor, source)

  def regenerate(id, actor, source) when is_binary(id) do
    case get(id) do
      nil ->
        {:error, :not_found}

      recommendation ->
        with {:ok, superseded} <- update_decision(recommendation, "superseded", "Regeneration requested", actor),
             {:ok, _job} <- enqueue_generation(recommendation.contact_id, source, force?: true) do
          audit_decision("outreach.recommendation_regeneration_requested", superseded, actor)
          {:ok, superseded}
        end
    end
  end

  def enqueue_generation(contact_id, source \\ "system", opts \\ []) when is_binary(contact_id) do
    force? = Keyword.get(opts, :force?, false)

    %{contact_id: contact_id, source: source, force: force?}
    |> GenerateRecommendation.new(
      unique: [
        period: 60,
        fields: [:worker, :args],
        keys: [:contact_id],
        states: [:available, :scheduled, :executing, :retryable]
      ]
    )
    |> Oban.insert()
  end

  def list_candidate_ids(opts \\ []) do
    limit = Keyword.get(opts, :limit, 25)

    new_event =
      from(event in Event,
        where:
          event.account_id == parent_as(:contact).account_id and
            (is_nil(event.contact_id) or event.contact_id == parent_as(:contact).id) and
            (is_nil(parent_as(:contact).outreach_recommendations_checked_at) or
               event.inserted_at > parent_as(:contact).outreach_recommendations_checked_at),
        select: 1
      )

    Contact
    |> from(as: :contact)
    |> join(:inner, [contact], account in Account, on: account.id == contact.account_id)
    |> where([contact], not is_nil(contact.outreach_enrolled_at))
    |> where([contact], contact.outreach_status != "not_interested")
    |> where(
      [contact, account],
      is_nil(contact.outreach_recommendations_checked_at) or exists(new_event) or
        account.updated_at > contact.outreach_recommendations_checked_at or
        (not is_nil(account.latest_activity_at) and
           account.latest_activity_at > contact.outreach_recommendations_checked_at)
    )
    |> order_by([contact],
      asc_nulls_first: contact.outreach_recommendations_checked_at,
      desc_nulls_last: contact.last_outreach_at,
      asc: contact.full_name
    )
    |> limit(^limit)
    |> select([contact], contact.id)
    |> Repo.all()
  end

  def mark_notified(%Recommendation{} = recommendation, attrs) when is_map(attrs) do
    now = utc_now()

    recommendation
    |> Recommendation.notification_changeset(%{
      slack_notification_posted_at: now,
      slack_notification_channel_id: attr(attrs, "channel_id", :channel_id),
      slack_notification_thread_ts: attr(attrs, "thread_ts", :thread_ts)
    })
    |> Repo.update()
    |> tap(fn
      {:ok, notified} -> audit_notification(notified)
      _result -> :ok
    end)
  end

  def handle_slack_action(action, recommendation_id, opts \\ []) do
    actor = slack_actor(opts)

    case get(recommendation_id) do
      %Recommendation{} = recommendation ->
        case action do
          "complete" ->
            with {:ok, result} <- complete(recommendation, actor),
                 :ok <- refresh_notification(result.recommendation, opts) do
              {:ok, %{message: "Next step marked complete."}}
            end

          "dismiss" ->
            with {:ok, dismissed} <- dismiss(recommendation, "Dismissed from Slack", actor),
                 :ok <- refresh_notification(dismissed, opts) do
              {:ok, %{message: "Suggestion dismissed."}}
            end

          "regenerate" ->
            with {:ok, superseded} <- regenerate(recommendation, actor, "slack"),
                 :ok <- refresh_notification(superseded, opts) do
              {:ok, %{message: "A fresh next step is being prepared."}}
            end

          _action ->
            {:error, :unsupported_action}
        end

      nil ->
        {:error, :not_found}
    end
  end

  defp context(contact_id) do
    case Repo.get(Contact, contact_id) do
      nil ->
        nil

      contact ->
        contact = Repo.preload(contact, :account)

        events =
          Event
          |> where(
            [event],
            event.account_id == ^contact.account_id and
              (is_nil(event.contact_id) or event.contact_id == ^contact.id)
          )
          |> order_by([event], desc: event.occurred_at, desc: event.inserted_at)
          |> limit(30)
          |> Repo.all()

        recommendations =
          Recommendation
          |> where([recommendation], recommendation.contact_id == ^contact.id)
          |> order_by([recommendation], desc: recommendation.inserted_at)
          |> limit(12)
          |> Repo.all()

        %{
          contact: contact,
          events: events,
          recommendations: recommendations,
          message_learning: MessageLearning.context(contact)
        }
    end
  end

  defp persist_generated(context, result) do
    raw = result |> generated_recommendations() |> List.first()

    case normalize_generated(context, raw) do
      {:ok, attrs} ->
        case replace_pending(context.contact, attrs) do
          {:ok, {recommendation, superseded}} ->
            Enum.each(
              superseded,
              &audit_decision("outreach.recommendation_superseded", &1, nil)
            )

            mark_checked(context.contact)
            enqueue_notification(recommendation)
            audit_generation(context.contact, recommendation, 1)
            {:ok, recommendation}

          {:error, reason} ->
            {:error, reason}
        end

      :skip ->
        mark_checked(context.contact)
        audit_generation(context.contact, nil, if(raw, do: 1, else: 0))
        {:ok, nil}
    end
  end

  defp normalize_generated(_context, nil), do: :skip

  defp normalize_generated(context, raw) when is_map(raw) do
    raw = stringify_keys(raw)
    action_type = raw["action_type"]
    evidence = valid_evidence(context.events, raw["evidence"])

    with {:ok, confidence} <- Decimal.cast(raw["confidence"]),
         true <- Decimal.compare(confidence, @minimum_confidence) in [:eq, :gt],
         true <- action_type in Recommendation.action_types(),
         true <- present?(raw["title"]) and present?(raw["guidance"]) and present?(raw["rationale"]),
         true <- valid_draft?(context.contact, action_type, raw["draft_subject"], raw["draft_message"]),
         true <- valid_message_strategy?(action_type, raw),
         true <- evidence != [],
         {:ok, due_in_days} <- cast_due_in_days(raw["due_in_days"]) do
      {:ok,
       %{
         "action_type" => action_type,
         "recommended_event_kind" => recommended_event_kind(action_type),
         "title" => normalize_generated_text(raw["title"]),
         "guidance" => normalize_generated_text(raw["guidance"]),
         "rationale" => normalize_generated_text(raw["rationale"]),
         "draft_subject" => generated_subject(action_type, raw["draft_subject"]),
         "draft_message" => generated_message(action_type, raw["draft_message"]),
         "due_at" => DateTime.add(utc_now(), due_in_days, :day),
         "confidence" => confidence,
         "evidence" => %{"items" => evidence},
         "source_event_id" => evidence |> List.first() |> Map.fetch!("event_id"),
         "generated_by_agent" => @agent_name,
         "metadata" =>
           %{
             "personalization_basis" => normalize_generated_text(raw["personalization_basis"]),
             "risks" => raw["risks"] |> normalize_string_list() |> Enum.map(&normalize_generated_text/1),
             "message_strategy" => message_strategy(action_type, raw),
             "learning_sample_size" => context.message_learning.total_evaluated
           }
           |> Enum.reject(fn {_key, value} -> value in [nil, %{}] end)
           |> Map.new()
       }}
    else
      _reason -> :skip
    end
  end

  defp normalize_generated(_context, _raw), do: :skip

  defp replace_pending(contact, attrs) do
    Repo.transaction(fn ->
      now = utc_now()

      superseded =
        Recommendation
        |> where([recommendation], recommendation.contact_id == ^contact.id and recommendation.status == "pending")
        |> Repo.all()
        |> Enum.map(fn recommendation ->
          recommendation
          |> Recommendation.decision_changeset(%{
            status: "superseded",
            reviewed_at: now,
            review_reason: "New account evidence"
          })
          |> Repo.update!()
        end)

      source_event_id = attrs["source_event_id"]

      recommendation =
        %Recommendation{
          contact_id: contact.id,
          account_id: contact.account_id,
          source_event_id: source_event_id,
          slack_notification_requested_at: now
        }
        |> Recommendation.changeset(Map.delete(attrs, "source_event_id"))
        |> Repo.insert!()

      link_evidence!(recommendation)

      {recommendation, superseded}
    end)
  rescue
    error in Ecto.InvalidChangesetError -> {:error, error.changeset}
  end

  defp generated_recommendations(%{"recommendations" => recommendations}) when is_list(recommendations),
    do: recommendations

  defp generated_recommendations(%{recommendations: recommendations}) when is_list(recommendations), do: recommendations

  defp generated_recommendations(_result), do: []

  defp valid_evidence(events, evidence) when is_list(evidence) do
    event_ids = MapSet.new(events, & &1.id)

    evidence
    |> Enum.map(&stringify_keys/1)
    |> Enum.filter(fn item ->
      MapSet.member?(event_ids, item["event_id"]) and present?(item["observation"])
    end)
    |> Enum.uniq_by(& &1["event_id"])
  end

  defp valid_evidence(_events, _evidence), do: []

  defp link_evidence!(%Recommendation{evidence: %{"items" => items}} = recommendation) when is_list(items) do
    evidence =
      Enum.map(items, fn item ->
        %{
          record_type: "account_event",
          record_id: item["event_id"],
          source_class: "observed",
          observation: item["observation"]
        }
      end)

    case Evidence.link_all("outreach_recommendation", recommendation.id, evidence) do
      {:ok, _links} -> :ok
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp valid_draft?(contact, "inmail", subject, draft), do: valid_inmail_subject?(contact, subject) and present?(draft)

  defp valid_draft?(_contact, "connection_request", subject, draft) do
    not present?(subject) and
      case normalize_optional_text(draft) do
        nil -> true
        note -> String.length(note) <= 200
      end
  end

  defp valid_draft?(_contact, action_type, subject, draft) when action_type in ~w(message reply follow_up),
    do: not present?(subject) and present?(draft)

  defp valid_draft?(_contact, _action_type, _subject, _draft), do: true

  defp valid_inmail_subject?(contact, subject) do
    subject = normalize_optional_text(subject)

    if subject do
      normalized = String.downcase(subject)
      word_count = subject |> String.split(~r/\s+/, trim: true) |> length()

      word_count in 2..6 and
        not Regex.match?(~r/^(connect|connecting|connection|let'?s connect|quick question)\b/iu, subject) and
        not includes_contact_identity?(normalized, contact)
    else
      false
    end
  end

  defp includes_contact_identity?(subject, contact) do
    [contact.full_name, contact.title]
    |> Enum.filter(&present?/1)
    |> Enum.map(&String.downcase/1)
    |> Enum.any?(&String.contains?(subject, &1))
  end

  defp generated_subject("inmail", subject), do: normalize_generated_text(subject)
  defp generated_subject(_action_type, _subject), do: nil

  defp generated_message(action_type, message)
       when action_type in ~w(connection_request inmail message reply follow_up), do: normalize_generated_text(message)

  defp generated_message(_action_type, _message), do: nil

  defp cast_due_in_days(days) when is_integer(days) and days >= 0 and days <= 30, do: {:ok, days}
  defp cast_due_in_days(_days), do: :error

  defp recommended_event_kind("connection_request"), do: "connection_requested"
  defp recommended_event_kind(action) when action in ~w(inmail message reply follow_up), do: "message_sent"
  defp recommended_event_kind(_action), do: "note"

  defp lock_pending(id) do
    Recommendation
    |> where([recommendation], recommendation.id == ^id and recommendation.status == "pending")
    |> lock("FOR UPDATE")
    |> preload(contact: :account)
    |> Repo.one()
  end

  defp update_decision(recommendation, status, reason, actor) do
    recommendation
    |> Recommendation.decision_changeset(%{
      status: status,
      reviewed_at: utc_now(),
      review_reason: reason
    })
    |> Ecto.Changeset.put_change(:reviewed_by_id, actor && actor.id)
    |> Repo.update()
  end

  defp record_completion(recommendation, completion, actor) do
    attrs = %{
      kind: recommendation.recommended_event_kind || "note",
      subject: completion.subject,
      body: completion_body(recommendation, completion.message),
      occurred_at: utc_now(),
      recommendation_id: recommendation.id
    }

    Outreach.record_event(recommendation.contact, attrs, actor)
  end

  defp completion_body(%Recommendation{recommended_event_kind: "connection_requested"} = recommendation, sent_message) do
    sent_message || recommendation.draft_message || recommendation.guidance
  end

  defp completion_body(%Recommendation{recommended_event_kind: "message_sent"} = recommendation, sent_message) do
    sent_message || recommendation.draft_message || recommendation.guidance
  end

  defp completion_body(recommendation, _sent_message) do
    "Completed suggested next step: #{recommendation.title}. #{recommendation.guidance}"
  end

  defp completion_content(
         %Recommendation{action_type: "inmail", recommended_event_kind: "message_sent"} = recommendation,
         attrs
       ) do
    sent_message =
      normalize_optional_text(attr(attrs, "sent_message", :sent_message)) || recommendation.draft_message

    sent_subject =
      normalize_optional_text(attr(attrs, "sent_subject", :sent_subject)) || recommendation.draft_subject

    case {sent_subject, sent_message} do
      {nil, _sent_message} -> {:error, :sent_subject_required}
      {_sent_subject, nil} -> {:error, :sent_message_required}
      {sent_subject, sent_message} -> {:ok, %{subject: sent_subject, message: sent_message}}
    end
  end

  defp completion_content(%Recommendation{recommended_event_kind: "message_sent"} = recommendation, attrs) do
    sent_message =
      normalize_optional_text(attr(attrs, "sent_message", :sent_message)) || recommendation.draft_message

    case sent_message do
      nil -> {:error, :sent_message_required}
      sent_message -> {:ok, %{subject: nil, message: sent_message}}
    end
  end

  defp completion_content(%Recommendation{recommended_event_kind: "connection_requested"} = recommendation, attrs) do
    sent_message =
      normalize_optional_text(attr(attrs, "sent_message", :sent_message)) || recommendation.draft_message

    {:ok, %{subject: nil, message: sent_message}}
  end

  defp completion_content(_recommendation, _attrs), do: {:ok, %{subject: nil, message: nil}}

  defp normalize_generated_text(value) do
    value
    |> normalize_optional_text()
    |> case do
      nil -> nil
      text -> String.replace(text, ~r/\s*—\s*/, ", ")
    end
  end

  defp completion_contact(%Recommendation{action_type: "stop", contact: contact}) do
    contact
    |> Ecto.Changeset.change(%{outreach_status: "not_interested"})
    |> Repo.update()
  end

  defp completion_contact(%Recommendation{contact: contact}), do: {:ok, contact}

  defp enqueue_after_completion(%Recommendation{action_type: "stop"}), do: :ok

  defp enqueue_after_completion(recommendation) do
    enqueue_generation(recommendation.contact_id, "recommendation_completed", force?: true)
  end

  defp message_strategy(action_type, raw) when action_type in ~w(inmail message reply follow_up) do
    strategy = %{
      "message_intent" => raw["message_intent"],
      "personalization_source" => raw["personalization_source"],
      "call_to_action" => raw["call_to_action"]
    }

    if strategy["message_intent"] in MessageAttempt.message_intents() and
         strategy["personalization_source"] in MessageAttempt.personalization_sources() and
         strategy["call_to_action"] in MessageAttempt.calls_to_action() do
      strategy
    else
      %{}
    end
  end

  defp message_strategy(_action_type, _raw), do: %{}

  defp valid_message_strategy?(action_type, raw) when action_type in ~w(inmail message reply follow_up),
    do: message_strategy(action_type, raw) != %{}

  defp valid_message_strategy?(_action_type, _raw), do: true

  defp mark_checked(contact) do
    contact
    |> Contact.outreach_recommendations_checked_changeset(%{outreach_recommendations_checked_at: utc_now()})
    |> Repo.update()
  end

  defp enqueue_notification(recommendation) do
    %{recommendation_id: recommendation.id}
    |> NotifyRecommendation.new(unique: [period: 300, fields: [:worker, :args]])
    |> Oban.insert()
  end

  defp refresh_notification(recommendation, opts) do
    case RecommendationNotifier.notify(get(recommendation.id), opts) do
      {:ok, _attrs} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp slack_actor(opts) do
    case Keyword.get(opts, :actor_email) do
      email when is_binary(email) and email != "" -> Users.get_user_by_email(email)
      _email -> nil
    end
  end

  defp audit_generation(contact, recommendation, considered_count) do
    Audit.record("outreach.recommendation_generated", %{
      target_type: "contact",
      target_id: contact.id,
      target_label: contact.full_name,
      metadata: %{
        "account_id" => contact.account_id,
        "created_count" => if(recommendation, do: 1, else: 0),
        "considered_count" => considered_count,
        "recommendation_id" => recommendation && recommendation.id,
        "path" => "/gtm/outreach/#{contact.id}"
      }
    })
  end

  defp audit_generation_request(contact, job, source, actor) do
    Audit.record(
      "outreach.recommendation_requested",
      %{
        target_type: "contact",
        target_id: contact.id,
        target_label: contact.full_name,
        metadata: %{
          "account_id" => contact.account_id,
          "job_id" => job.id,
          "source" => source,
          "path" => "/gtm/outreach/#{contact.id}"
        }
      },
      actor: actor
    )
  end

  defp audit_decision(action, recommendation, actor) do
    Audit.record(
      action,
      %{
        target_type: "outreach_recommendation",
        target_id: recommendation.id,
        target_label: recommendation.title,
        metadata: %{
          "account_id" => recommendation.account_id,
          "contact_id" => recommendation.contact_id,
          "action_type" => recommendation.action_type,
          "status" => recommendation.status,
          "review_reason" => recommendation.review_reason,
          "path" => "/gtm/outreach/#{recommendation.contact_id}"
        }
      },
      actor: actor
    )
  end

  defp audit_notification(recommendation) do
    Audit.record("outreach.recommendation_notified", %{
      target_type: "outreach_recommendation",
      target_id: recommendation.id,
      target_label: recommendation.title,
      metadata: %{
        "account_id" => recommendation.account_id,
        "contact_id" => recommendation.contact_id,
        "slack_channel_id" => recommendation.slack_notification_channel_id,
        "slack_thread_ts" => recommendation.slack_notification_thread_ts,
        "path" => "/gtm/outreach/#{recommendation.contact_id}"
      }
    })
  end

  defp maybe_filter_statuses(query, nil), do: query
  defp maybe_filter_statuses(query, []), do: query
  defp maybe_filter_statuses(query, statuses), do: where(query, [recommendation], recommendation.status in ^statuses)

  defp normalize_string_list(values) when is_list(values) do
    values
    |> Enum.map(&normalize_optional_text/1)
    |> Enum.reject(&is_nil/1)
  end

  defp normalize_string_list(_values), do: []
end
