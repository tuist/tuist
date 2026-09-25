defmodule Atlas.Nudges do
  @moduledoc """
  Account outreach nudges: signals detect a moment worth reaching out about
  and drop a card into Slack that a human claims, edits, and sends.

  The pipeline is:

    1. `Atlas.Nudges.Workers.EvaluateSignals` fans one job per
       (signal, account) into `EvaluateSignalForAccount`.
    2. That job runs the signal's `evaluate/1`. On a fresh threshold
       crossing it opens a `SignalEpisode`, then calls `propose/3`.
    3. `propose/3` inserts an `account_nudges` row in `pending_post`,
       guarded by the partial-unique dedup index and the per-account rate
       limit under a `SELECT ... FOR UPDATE` on the accounts row.
    4. `PostNudgeCard` picks up pending rows, posts to Slack via an outbox
       attempt row, and transitions to `proposed`.
    5. Slack buttons flow through `Atlas.Slack.Interactions` into `claim/2`,
       `release/1`, `dismiss/3`, all under `SELECT ... FOR UPDATE`.
    6. `ExpireStaleNudges` sweeps rows past `expires_at` to `expired`.
  """

  import Ecto.Query

  alias Atlas.Accounts.Account
  alias Atlas.Accounts.Contact
  alias Atlas.Audit
  alias Atlas.GTM
  alias Atlas.GTM.Delivery
  alias Atlas.Nudges.Nudge
  alias Atlas.Nudges.Proposal
  alias Atlas.Nudges.SignalEpisode
  alias Atlas.Nudges.SlackPostAttempt
  alias Atlas.Repo
  alias Atlas.Users
  alias Atlas.Users.User
  alias Ecto.Multi

  @open_nudges_per_account 3
  @deliver_worker "Atlas.GTM.Workers.DeliverDirectEmail"
  @active_oban_states ~w(available scheduled executing retryable)

  @doc "Open nudges for an account, newest first."
  def list_open_nudges(%Account{id: account_id}), do: list_open_nudges(account_id)

  def list_open_nudges(account_id) when is_binary(account_id) do
    Nudge
    |> where([n], n.account_id == ^account_id and n.state in ^Nudge.open_states())
    |> order_by([n], desc: n.inserted_at)
    |> Repo.all()
  end

  @doc "All nudges for an account, newest first, optionally filtered by state."
  def list_nudges(account_or_id, opts \\ [])

  def list_nudges(%Account{id: account_id}, opts), do: list_nudges(account_id, opts)

  def list_nudges(account_id, opts) when is_binary(account_id) do
    states = Keyword.get(opts, :states)
    limit = Keyword.get(opts, :limit, 50)

    Nudge
    |> where([n], n.account_id == ^account_id)
    |> maybe_filter_states(states)
    |> order_by([n], desc: n.inserted_at)
    |> limit(^limit)
    |> preload(:email_delivery)
    |> Repo.all()
  end

  def get_nudge(id) when is_binary(id), do: Repo.get(Nudge, id)

  @doc """
  Ensures an open episode exists for the given signal on this account.
  Returns `{:opened, episode}` on a fresh open, `{:existing, episode}`
  when one was already open.
  """
  def open_or_touch_episode(%Account{id: account_id}, signal, evidence \\ %{}) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    case Repo.get_by(SignalEpisode, account_id: account_id, signal: signal, state: "open") do
      %SignalEpisode{} = existing ->
        {:existing, existing}

      nil ->
        %SignalEpisode{}
        |> SignalEpisode.open_changeset(%{
          account_id: account_id,
          signal: signal,
          evidence: evidence
        })
        |> Repo.insert()
        |> case do
          {:ok, episode} ->
            {:opened, %{episode | opened_at: episode.opened_at || now}}

          {:error, %Ecto.Changeset{errors: errors}} ->
            if unique_error?(errors) do
              episode =
                Repo.get_by!(SignalEpisode,
                  account_id: account_id,
                  signal: signal,
                  state: "open"
                )

              {:existing, episode}
            else
              {:error, errors}
            end
        end
    end
  end

  defp unique_error?(errors) do
    Enum.any?(errors, fn {_field, {msg, _}} ->
      String.contains?(msg, "already been taken") or String.contains?(msg, "unique") or
        String.contains?(msg, "has already been taken")
    end)
  end

  @doc "Closes the open episode for this account/signal, if any."
  def close_episode(%Account{id: account_id}, signal) do
    case Repo.get_by(SignalEpisode, account_id: account_id, signal: signal, state: "open") do
      nil ->
        :ok

      episode ->
        episode
        |> SignalEpisode.close_changeset()
        |> Repo.update()
        |> case do
          {:ok, _closed} -> :ok
          {:error, _reason} = err -> err
        end
    end
  end

  @doc """
  Creates a nudge from a proposal in `pending_post`. Skips when a duplicate
  is already open (partial-unique dedup) or the account is at its open-
  nudge rate limit. Locks the account row for the rate check so two
  concurrent evaluators can't both squeeze past the cap.
  """
  def propose(%Account{id: account_id} = account, signal, %Proposal{} = proposal) do
    Multi.new()
    |> Multi.run(:lock_account, &lock_account(&1, &2, account_id))
    |> Multi.run(:rate_check, &rate_check(&1, &2, account_id))
    |> Multi.insert(:nudge, build_nudge_changeset(account, signal, proposal))
    |> Repo.transaction()
    |> translate_propose_result()
  end

  defp lock_account(repo, _changes, account_id) do
    case repo.one(from a in Account, where: a.id == ^account_id, lock: "FOR UPDATE") do
      nil -> {:error, :account_not_found}
      %Account{} = locked -> {:ok, locked}
    end
  end

  defp rate_check(repo, _changes, account_id) do
    open_count =
      repo.aggregate(
        from(n in Nudge,
          where: n.account_id == ^account_id and n.state in ^Nudge.open_states()
        ),
        :count,
        :id
      )

    if open_count >= @open_nudges_per_account do
      {:error, :rate_limited}
    else
      {:ok, open_count}
    end
  end

  defp build_nudge_changeset(%Account{id: account_id}, signal, %Proposal{} = proposal) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    expires_at = DateTime.add(now, proposal.expires_in_days * 86_400, :second)

    Nudge.create_changeset(%Nudge{}, %{
      account_id: account_id,
      contact_id: proposal.contact_id,
      signal: signal,
      dedup_key: proposal.dedup_key,
      severity: proposal.severity,
      title: proposal.title,
      rationale: proposal.rationale,
      evidence: proposal.evidence,
      draft_subject: proposal.draft_subject,
      draft_body: proposal.draft_body,
      expires_at: expires_at
    })
  end

  defp translate_propose_result({:ok, %{nudge: nudge}}), do: {:ok, nudge}

  defp translate_propose_result({:error, :lock_account, :account_not_found, _}), do: {:skip, :account_not_found}

  defp translate_propose_result({:error, :rate_check, :rate_limited, _}), do: {:skip, :rate_limited}

  defp translate_propose_result({:error, :nudge, %Ecto.Changeset{errors: errors}, _}) do
    if unique_error?(errors), do: {:skip, :duplicate}, else: {:error, errors}
  end

  @doc """
  Picks a contact to draft the nudge email to. Excludes contacts without a
  reachable email (missing, bounced, or opted out) and ranks the survivors
  so a decision maker beats the flagged-primary contact, which in turn
  beats a plain contact; ties break on the earliest insertion. Returns
  `nil` when no contact qualifies.
  """
  def select_contact_for(%Account{id: account_id}) do
    Contact
    |> where([c], c.account_id == ^account_id)
    |> where([c], not is_nil(c.email) and c.email != "")
    |> where([c], is_nil(c.bounced_at))
    |> where([c], is_nil(c.opted_out_at))
    |> order_by([c],
      desc: c.is_decision_maker,
      desc: c.is_primary,
      asc: c.inserted_at
    )
    |> limit(1)
    |> Repo.one()
  end

  @doc """
  Records a fresh Slack post attempt for a nudge and returns the row.
  Uses `on_conflict: :nothing` on `client_msg_id` so a retry after a crash
  reuses the existing attempt row (the outbox worker then reconciles via
  `Atlas.Slack.API.find_message_by_metadata/4` before re-posting).
  """
  def get_or_create_post_attempt(%Nudge{} = nudge, channel_id) do
    client_msg_id = post_attempt_client_msg_id(nudge)

    case Repo.get_by(SlackPostAttempt, client_msg_id: client_msg_id) do
      %SlackPostAttempt{} = existing ->
        {:ok, existing}

      nil ->
        %SlackPostAttempt{}
        |> SlackPostAttempt.create_changeset(%{
          nudge_id: nudge.id,
          client_msg_id: client_msg_id,
          channel_id: channel_id
        })
        |> Repo.insert()
        |> case do
          {:ok, attempt} ->
            {:ok, attempt}

          {:error, %Ecto.Changeset{errors: errors}} ->
            if unique_error?(errors) do
              {:ok, Repo.get_by!(SlackPostAttempt, client_msg_id: client_msg_id)}
            else
              {:error, errors}
            end
        end
    end
  end

  def post_attempt_client_msg_id(%Nudge{id: id}), do: "atlas-nudge-#{id}"

  def mark_post_attempt_posted(%SlackPostAttempt{} = attempt, message_ts) do
    attempt |> SlackPostAttempt.posted_changeset(message_ts) |> Repo.update()
  end

  def mark_post_attempt_failed(%SlackPostAttempt{} = attempt, error) do
    attempt |> SlackPostAttempt.failed_changeset(error) |> Repo.update()
  end

  def mark_nudge_posted(%Nudge{} = nudge, channel_id, message_ts) do
    nudge
    |> Nudge.mark_posted_changeset(%{
      slack_channel_id: channel_id,
      slack_message_ts: message_ts
    })
    |> Repo.update()
  end

  @doc "Claim a nudge under a row lock. `actor` is the Atlas user."
  def claim(nudge_id, %User{} = actor) when is_binary(nudge_id) do
    with_locked_nudge(nudge_id, fn nudge ->
      nudge |> Nudge.claim_changeset(actor) |> Repo.update()
    end)
  end

  @doc "Release a claimed nudge back to the queue."
  def release(nudge_id) when is_binary(nudge_id) do
    with_locked_nudge(nudge_id, fn nudge ->
      nudge |> Nudge.release_changeset() |> Repo.update()
    end)
  end

  @doc "Dismiss a nudge with a required reason, optionally muting future signals until `dismissed_until`."
  def dismiss(nudge_id, attrs) when is_binary(nudge_id) and is_map(attrs) do
    with_locked_nudge(nudge_id, fn nudge ->
      nudge |> Nudge.dismiss_changeset(attrs) |> Repo.update()
    end)
  end

  @doc """
  Queues the drafted email via `Atlas.GTM.DirectEmails` and transitions the
  nudge to `sent`. Requires the actor to be either the claimant or hold the
  `admin:write` scope. Reloads and revalidates the frozen `contact_id` before
  queueing; never re-selects a different contact.
  """
  def send(nudge_id, %User{} = actor) when is_binary(nudge_id) do
    Repo.transaction(fn ->
      case Repo.one(from n in Nudge, where: n.id == ^nudge_id, lock: "FOR UPDATE") do
        nil ->
          Repo.rollback(:not_found)

        nudge ->
          with :ok <- authorize_send(nudge, actor),
               :ok <- ensure_claimed(nudge),
               {:ok, contact} <- reload_and_validate_contact(nudge),
               {:ok, %{delivery: delivery, duplicate: duplicate?}} <-
                 queue_delivery(nudge, contact, actor),
               {:ok, updated} <- Repo.update(Nudge.send_changeset(nudge, delivery)) do
            audit_sent(updated, contact, delivery, duplicate?, actor)
            %{updated | email_delivery: delivery, duplicate: duplicate?}
          else
            {:error, reason} -> Repo.rollback(reason)
          end
      end
    end)
  end

  @doc """
  Moves a nudge whose delivery is terminally failed back to `claimed` so the
  operator can Send again. Refuses if the delivery is still retrying
  (`delivery_stage/1 == :retrying`) so we never race with an in-flight Oban
  retry.
  """
  def retry(nudge_id) when is_binary(nudge_id) do
    with_locked_nudge(nudge_id, fn nudge ->
      delivery = load_delivery(nudge)

      case delivery_stage(delivery) do
        :failed -> nudge |> Nudge.retry_changeset() |> Repo.update()
        stage -> {:error, {:retry_not_allowed, stage}}
      end
    end)
  end

  @doc """
  Records that we have observed and reflected the delivery's terminal status
  in the Slack card. Called by the reconciler worker.
  """
  def observe_delivery(%Nudge{} = nudge) do
    nudge |> Nudge.observe_delivery_changeset() |> Repo.update()
  end

  @doc """
  Nudges in `sent` state with a linked delivery whose current stage is
  `:delivered` or `:failed` and whose `email_delivery_observed_at` is nil.
  The reconciler worker refreshes each row's Slack card and stamps the
  observed_at timestamp.
  """
  def list_nudges_for_reconciliation(limit \\ 100) do
    Nudge
    |> where([n], n.state == "sent" and is_nil(n.email_delivery_observed_at))
    |> where([n], not is_nil(n.email_delivery_id))
    |> limit(^limit)
    |> Repo.all()
    |> Enum.map(fn nudge ->
      delivery = load_delivery(nudge)
      %{nudge: nudge, delivery: delivery, stage: delivery_stage(delivery)}
    end)
    |> Enum.filter(fn %{stage: stage} -> stage in [:delivered, :failed] end)
  end

  @doc """
  The observable stage of a nudge's linked delivery:

    * `:pending` — delivery is queued but has not yet been attempted.
    * `:retrying` — a delivery attempt failed and Oban has retries queued.
    * `:delivered` — the provider accepted the message.
    * `:failed` — Oban's automatic retries are exhausted.
  """
  def delivery_stage(nil), do: :pending
  def delivery_stage(%Delivery{status: "delivered"}), do: :delivered

  def delivery_stage(%Delivery{status: "failed", id: id}) do
    if any_active_deliver_job?(id), do: :retrying, else: :failed
  end

  def delivery_stage(%Delivery{}), do: :pending

  @doc """
  Resolves the current delivery stage from a nudge, loading the delivery on
  demand when the association is unset or unloaded.
  """
  def stage_for(%Nudge{email_delivery_id: nil}), do: :pending
  def stage_for(%Nudge{email_delivery: %Delivery{} = delivery}), do: delivery_stage(delivery)
  def stage_for(%Nudge{} = nudge), do: nudge |> load_delivery() |> delivery_stage()

  defp load_delivery(%Nudge{email_delivery_id: nil}), do: nil
  defp load_delivery(%Nudge{email_delivery_id: id}), do: Repo.get(Delivery, id)

  defp any_active_deliver_job?(delivery_id) when is_binary(delivery_id) do
    Repo.exists?(
      from j in "oban_jobs",
        where:
          j.worker == ^@deliver_worker and
            fragment("?->>'delivery_id' = ?", j.args, ^delivery_id) and
            j.state in ^@active_oban_states
    )
  end

  defp authorize_send(%Nudge{claimed_by_user_id: user_id}, %User{id: user_id}), do: :ok

  defp authorize_send(_nudge, %User{} = actor) do
    if Users.has_scope?(actor, "admin:write"), do: :ok, else: {:error, :not_authorized}
  end

  defp ensure_claimed(%Nudge{state: "claimed"}), do: :ok
  defp ensure_claimed(%Nudge{state: state}), do: {:error, {:invalid_state, state}}

  defp reload_and_validate_contact(%Nudge{contact_id: nil}), do: {:error, :contact_missing}

  defp reload_and_validate_contact(%Nudge{contact_id: contact_id}) do
    case Repo.get(Contact, contact_id) do
      nil -> {:error, :contact_missing}
      %Contact{email: email} when is_nil(email) or email == "" -> {:error, :contact_email_missing}
      %Contact{bounced_at: bounced} when not is_nil(bounced) -> {:error, :contact_bounced}
      %Contact{opted_out_at: opted} when not is_nil(opted) -> {:error, :contact_opted_out}
      %Contact{} = contact -> {:ok, contact}
    end
  end

  defp queue_delivery(%Nudge{} = nudge, %Contact{} = contact, %User{} = actor) do
    account = Repo.get(Account, nudge.account_id)

    GTM.queue_direct_email(
      %{
        recipient_email: contact.email,
        recipient_name: contact.full_name,
        subject: nudge.draft_subject,
        body_markdown: nudge.draft_body,
        account: account
      },
      actor
    )
  end

  defp audit_sent(%Nudge{} = nudge, %Contact{} = contact, %Delivery{} = delivery, duplicate?, actor) do
    Audit.record(
      "nudge.sent",
      %{
        target_type: "nudge",
        target_id: nudge.id,
        target_label: nudge.title,
        metadata: %{
          "nudge_id" => nudge.id,
          "delivery_id" => delivery.id,
          "duplicate" => duplicate?,
          "recipient_email" => contact.email,
          "contact_id" => contact.id,
          "subject" => nudge.draft_subject,
          "body_digest" => body_digest(nudge.draft_body),
          "signal" => nudge.signal,
          "account_id" => nudge.account_id,
          "path" => "/commercial/sales/accounts/#{nudge.account_id}"
        }
      },
      actor: actor
    )
  end

  defp body_digest(body) when is_binary(body) do
    :crypto.hash(:sha256, body) |> Base.encode16(case: :lower)
  end

  @doc """
  Sweeps open nudges past `expires_at` to `expired`. Returns the list of
  expired nudge ids so the caller (worker) can update the Slack cards.
  """
  def expire_stale(now \\ DateTime.utc_now() |> DateTime.truncate(:second)) do
    Nudge
    |> where([n], n.state in ^Nudge.open_states() and n.expires_at <= ^now)
    |> Repo.all()
    |> Enum.flat_map(fn nudge ->
      case with_locked_nudge(nudge.id, fn locked ->
             locked |> Nudge.expire_changeset() |> Repo.update()
           end) do
        {:ok, expired} -> [expired]
        _other -> []
      end
    end)
  end

  defp with_locked_nudge(id, fun) do
    Repo.transaction(fn ->
      case Repo.one(from n in Nudge, where: n.id == ^id, lock: "FOR UPDATE") do
        nil ->
          Repo.rollback(:not_found)

        nudge ->
          case fun.(nudge) do
            {:ok, updated} -> updated
            {:error, reason} -> Repo.rollback(reason)
          end
      end
    end)
  end

  defp maybe_filter_states(query, nil), do: query
  defp maybe_filter_states(query, []), do: query
  defp maybe_filter_states(query, states), do: where(query, [n], n.state in ^states)
end
