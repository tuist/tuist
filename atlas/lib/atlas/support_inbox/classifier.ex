defmodule Atlas.SupportInbox.Classifier do
  @moduledoc """
  Orchestrates classification of a newly ingested inbound support email.

  Two paths:

    * **Thread-continuity gate.** If the inbound landed on a thread
      that has already had activity beyond the inbound itself — a
      team reply, a private note, or an earlier customer message —
      it is part of a live conversation, and we always ping
      `#support` without running the LLM. Live conversations are
      the last place we want a classifier deciding to stay silent.

    * **Fresh inbound.** For the first inbound on a new thread, we
      call `Atlas.SupportInbox.Agents.ClassifierAgent` and persist
      the decision on the thread so the notifier can route it.

  The returned decision is the source of truth for whether the
  Slack notification fires and where it goes; the caller passes it
  into `Atlas.Support.Workers.PostNotification.enqueue/3` as
  routing metadata.
  """

  import Ecto.Query, only: [from: 2]

  alias Atlas.Audit
  alias Atlas.Repo
  alias Atlas.Support.Message
  alias Atlas.Support.Thread
  alias Atlas.SupportInbox.Agents.ClassifierAgent

  require Logger

  @low_confidence_floor 0.7

  @type decision :: %{
          category: atom(),
          action_needed: boolean(),
          urgency: atom(),
          confidence: float(),
          reason: String.t(),
          source: :continuity | :classifier | :fallback,
          low_confidence?: boolean()
        }

  @doc """
  Classify a freshly ingested inbound and persist the decision on
  the thread. Always returns `{:ok, decision}` — a failed LLM call
  collapses to a fallback decision with `source: :fallback` and
  `action_needed: true` so the notifier still pings `#support`.
  Callers can rely on this: no `{:error, _}` branch is emitted.
  """
  def classify_and_persist(%Thread{} = thread, %Message{} = message, opts \\ []) do
    with {:ok, decision} <- classify(thread, message, opts) do
      persist(thread, decision)
      audit(thread, decision)
      {:ok, decision}
    end
  end

  @doc """
  Classify without persisting. Useful in tests and in the digest
  job. Prefer `classify_and_persist/3` for real inbound handling.
  """
  def classify(%Thread{} = thread, %Message{} = message, opts \\ []) do
    if continuing_conversation?(thread, message) do
      {:ok, continuity_decision()}
    else
      run_classifier(thread, message, opts)
    end
  end

  defp continuing_conversation?(%Thread{} = thread, %Message{} = message) do
    count = prior_activity_count(thread, message)
    count > 0
  end

  defp prior_activity_count(%Thread{id: thread_id}, %Message{id: message_id}) do
    from(m in Message,
      where: m.thread_id == ^thread_id and m.id != ^message_id,
      select: count(m.id)
    )
    |> Repo.one() || 0
  end

  defp continuity_decision do
    %{
      category: :support,
      action_needed: true,
      urgency: :normal,
      confidence: 1.0,
      reason: "Reply on an existing support thread; skipped classification.",
      source: :continuity,
      low_confidence?: false
    }
  end

  defp run_classifier(%Thread{} = thread, %Message{} = message, opts) do
    input = build_input(thread, message)
    classifier = Keyword.get(opts, :classifier, &ClassifierAgent.classify/1)

    case classifier.(input) do
      {:ok, decision} ->
        {:ok, wrap_classifier_decision(decision)}

      {:error, reason} ->
        Logger.warning(
          "SupportInbox classifier failed for thread #{thread.id}: #{inspect(reason)}. " <>
            "Falling back to #support ping."
        )

        {:ok, fallback_decision(reason)}
    end
  end

  defp build_input(%Thread{} = thread, %Message{} = message) do
    %{
      from: message_sender(thread, message),
      subject: thread.subject,
      body: message.body,
      exclude_thread_id: thread.id
    }
  end

  defp message_sender(%Thread{customer_email: email}, _message) when is_binary(email), do: email
  defp message_sender(_thread, _message), do: "(unknown sender)"

  defp wrap_classifier_decision(decision) do
    low_confidence? = decision.confidence < @low_confidence_floor

    decision
    |> Map.put(:source, :classifier)
    |> Map.put(:low_confidence?, low_confidence?)
    |> maybe_promote_low_confidence(low_confidence?)
  end

  # A low-confidence "silence" is treated as an action-needed ping —
  # a mis-silenced support thread is the failure mode we won't
  # accept, so we bias toward the visible outcome and flag it so
  # humans can spot the classifier missing.
  defp maybe_promote_low_confidence(decision, true) do
    decision
    |> Map.put(:action_needed, true)
    |> Map.update(:urgency, :normal, fn urgency ->
      if urgency in [:none, :low], do: :normal, else: urgency
    end)
  end

  defp maybe_promote_low_confidence(decision, false), do: decision

  defp fallback_decision(reason) do
    %{
      category: :other,
      action_needed: true,
      urgency: :normal,
      confidence: 0.0,
      reason: "Classifier failed (#{inspect(reason)}); defaulted to #support.",
      source: :fallback,
      low_confidence?: true
    }
  end

  defp persist(%Thread{} = thread, %{} = decision) do
    thread
    |> Thread.classification_changeset(%{
      classification: Atom.to_string(decision.category),
      action_needed: decision.action_needed,
      urgency: Atom.to_string(decision.urgency),
      classifier_confidence: decision.confidence,
      classifier_reason: decision.reason,
      classified_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
    |> Repo.update()
    |> case do
      {:ok, _thread} ->
        :ok

      {:error, changeset} ->
        Logger.warning(
          "SupportInbox failed to persist classification for thread #{thread.id}: " <>
            inspect(changeset.errors)
        )

        :ok
    end
  end

  defp audit(%Thread{} = thread, %{} = decision) do
    Audit.with_context(%{interface: "worker"}, fn ->
      Audit.record("support.thread_classified", %{
        target_type: "support_thread",
        target_id: thread.id,
        target_label: thread.subject,
        metadata: %{
          "dashboard_path" => "/commercial/support/#{thread.id}",
          "category" => Atom.to_string(decision.category),
          "action_needed" => decision.action_needed,
          "urgency" => Atom.to_string(decision.urgency),
          "confidence" => decision.confidence,
          "source" => Atom.to_string(decision.source),
          "low_confidence" => decision.low_confidence?,
          "reason" => decision.reason
        }
      })
    end)
  end
end
