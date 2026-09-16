defmodule Atlas.Accounts.OutcomeProposals do
  @moduledoc """
  Persists, reviews, and applies agent-generated outcome proposals.
  """

  import Ecto.Query

  alias Atlas.Accounts.Account
  alias Atlas.Accounts.Agents.OutcomeProposalAgent
  alias Atlas.Accounts.Event
  alias Atlas.Accounts.Outcome
  alias Atlas.Accounts.OutcomeProposal
  alias Atlas.Accounts.OutcomeReview
  alias Atlas.Accounts.Query
  alias Atlas.Audit
  alias Atlas.Evidence
  alias Atlas.Repo
  alias Atlas.Search

  require Logger

  @minimum_confidence Decimal.new("0.70")
  @agent_name "outcome_proposal_agent"

  def list(account_or_id, opts \\ [])

  def list(%Account{id: account_id}, opts), do: list(account_id, opts)

  def list(account_id, opts) when is_binary(account_id) do
    statuses = Keyword.get(opts, :statuses, ["pending"])

    OutcomeProposal
    |> where([proposal], proposal.account_id == ^account_id)
    |> maybe_filter_statuses(statuses)
    |> order_by([proposal],
      asc: fragment("CASE ? WHEN 'pending' THEN 0 WHEN 'approved' THEN 1 ELSE 2 END", proposal.status),
      desc: proposal.inserted_at
    )
    |> preload([:outcome, :source_event, :reviewed_by])
    |> Repo.all()
  end

  def get(id) when is_binary(id) do
    OutcomeProposal
    |> preload([:account, :outcome, :source_event, :reviewed_by])
    |> Repo.get(id)
  end

  def get(%Account{id: account_id}, id) when is_binary(id) do
    OutcomeProposal
    |> where([proposal], proposal.account_id == ^account_id)
    |> preload([:outcome, :source_event, :reviewed_by])
    |> Repo.get(id)
  end

  def change(%OutcomeProposal{} = proposal, attrs \\ %{}) do
    OutcomeProposal.edit_changeset(proposal, attrs)
  end

  def create(%Account{} = account, attrs) when is_map(attrs) do
    attrs = stringify_keys(attrs)
    proposal_type = attrs["proposal_type"]
    outcome_id = attrs["outcome_id"]
    source_event_id = attrs["source_event_id"] || first_evidence_event_id(attrs["evidence"])

    attrs =
      attrs
      |> Map.put_new("status", "pending")
      |> Map.put_new("generated_by_agent", @agent_name)
      |> Map.put("proposal_key", OutcomeProposal.proposal_key(proposal_type, outcome_id, attrs))

    changeset =
      %OutcomeProposal{
        account_id: account.id,
        outcome_id: outcome_id,
        source_event_id: source_event_id
      }
      |> OutcomeProposal.changeset(attrs)
      |> validate_account_ownership(account)

    Repo.transaction(fn ->
      case Repo.insert(changeset) do
        {:ok, proposal} ->
          link_evidence!("account_outcome_proposal", proposal.id, proposal.evidence)
          audit_proposal("account_outcome_proposal.created", proposal, %{})
          proposal

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  def update(%OutcomeProposal{} = proposal, attrs, actor \\ nil) when is_map(attrs) do
    account = Repo.get!(Account, proposal.account_id)
    changeset = OutcomeProposal.edit_changeset(proposal, attrs)

    changeset =
      if proposal.proposal_type == "new_outcome" do
        title = Ecto.Changeset.get_field(changeset, :title)
        motion = Ecto.Changeset.get_field(changeset, :motion)
        key = OutcomeProposal.proposal_key("new_outcome", nil, %{title: title, motion: motion})
        Ecto.Changeset.put_change(changeset, :proposal_key, key)
      else
        changeset
      end

    changeset
    |> validate_account_ownership(account)
    |> Repo.update()
    |> tap(fn
      {:ok, updated} -> audit_proposal("account_outcome_proposal.updated", updated, changeset, actor: actor)
      _result -> :ok
    end)
  end

  def reject(%OutcomeProposal{} = proposal, reason, actor \\ nil) do
    now = utc_now()

    proposal
    |> OutcomeProposal.decision_changeset(%{
      status: "rejected",
      rejection_reason: reason,
      reviewed_at: now
    })
    |> Ecto.Changeset.put_change(:reviewed_by_id, actor && actor.id)
    |> Repo.update()
    |> tap(fn
      {:ok, rejected} -> audit_proposal("account_outcome_proposal.rejected", rejected, %{}, actor: actor)
      _result -> :ok
    end)
  end

  def approve(%OutcomeProposal{id: id}, actor \\ nil) do
    Repo.transaction(fn ->
      proposal =
        OutcomeProposal
        |> where([proposal], proposal.id == ^id)
        |> lock("FOR UPDATE")
        |> preload([:account, :outcome])
        |> Repo.one()

      case proposal do
        nil -> Repo.rollback(:not_found)
        %OutcomeProposal{status: status} when status != "pending" -> Repo.rollback(:not_pending)
        %OutcomeProposal{} -> apply_and_approve(proposal, actor)
      end
    end)
  end

  def generate(account_id) when is_binary(account_id) do
    case Query.get_account(account_id) do
      nil ->
        {:error, :not_found}

      account ->
        case OutcomeProposalAgent.propose(account) do
          {:ok, result} -> persist_generated(account, result)
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp persist_generated(account, result) do
    proposals = result |> generated_proposals() |> Enum.take(3)

    created =
      proposals
      |> Enum.map(&normalize_generated(account, &1))
      |> Enum.flat_map(fn
        {:ok, attrs} ->
          case create(account, attrs) do
            {:ok, proposal} -> [proposal]
            {:error, _changeset} -> []
          end

        :skip ->
          []
      end)

    mark_checked(account)
    audit_generation(account, created, length(proposals))
    {:ok, created}
  end

  defp normalize_generated(account, raw) when is_map(raw) do
    raw = stringify_keys(raw)
    proposal_type = raw["proposal_type"]
    outcome = outcome_for(account, proposal_type, raw["outcome_id"])
    evidence = valid_evidence(account, raw["evidence"])

    with {:ok, confidence} <- cast_confidence(raw["confidence"]),
         true <- Decimal.compare(confidence, @minimum_confidence) in [:eq, :gt],
         true <- evidence != [],
         true <- valid_generated_shape?(proposal_type, outcome, raw) do
      attrs =
        raw
        |> Map.take([
          "proposal_type",
          "title",
          "description",
          "motion",
          "success_measure",
          "baseline",
          "target",
          "target_date",
          "health",
          "summary",
          "recommendation",
          "rationale"
        ])
        |> Map.put("outcome_id", outcome && outcome.id)
        |> Map.put("evidence", %{"items" => evidence})
        |> Map.put("source_event_id", evidence |> List.first() |> Map.get("event_id"))
        |> Map.put("confidence", confidence)
        |> Map.put("generated_by_agent", @agent_name)

      if new_evidence_after_rejection?(account, attrs, evidence), do: {:ok, attrs}, else: :skip
    else
      _reason -> :skip
    end
  end

  defp normalize_generated(_account, _raw), do: :skip

  defp outcome_for(account, "outcome_review", outcome_id) when is_binary(outcome_id) do
    Enum.find(account.outcomes, &(&1.id == outcome_id and &1.status == "active"))
  end

  defp outcome_for(_account, _proposal_type, _outcome_id), do: nil

  defp valid_generated_shape?("new_outcome", _outcome, raw) do
    present?(raw["title"]) and raw["motion"] in Outcome.motions()
  end

  defp valid_generated_shape?("outcome_review", %Outcome{}, raw) do
    raw["health"] in Outcome.health_values() and present?(raw["summary"])
  end

  defp valid_generated_shape?(_proposal_type, _outcome, _raw), do: false

  defp valid_evidence(account, evidence) when is_list(evidence) do
    event_ids = MapSet.new(account.events, & &1.id)

    evidence
    |> Enum.map(&stringify_keys/1)
    |> Enum.filter(fn item ->
      MapSet.member?(event_ids, item["event_id"]) and present?(item["observation"])
    end)
    |> Enum.uniq_by(& &1["event_id"])
  end

  defp valid_evidence(_account, _evidence), do: []

  defp new_evidence_after_rejection?(account, attrs, evidence) do
    proposal_key = OutcomeProposal.proposal_key(attrs["proposal_type"], attrs["outcome_id"], attrs)

    rejected =
      Enum.find(account.outcome_proposals, fn proposal ->
        proposal.status == "rejected" and proposal.proposal_key == proposal_key
      end)

    case rejected do
      nil ->
        true

      proposal ->
        rejected_event_ids = evidence_event_ids(proposal.evidence)
        Enum.any?(evidence, &(Map.get(&1, "event_id") not in rejected_event_ids))
    end
  end

  defp evidence_event_ids(%{"items" => items}) when is_list(items) do
    Enum.map(items, &(Map.get(&1, "event_id") || Map.get(&1, :event_id)))
  end

  defp evidence_event_ids(_evidence), do: []

  defp apply_and_approve(%OutcomeProposal{proposal_type: "new_outcome"} = proposal, actor) do
    outcome =
      %Outcome{
        account_id: proposal.account_id,
        owner_id: actor && actor.id,
        source_event_id: proposal.source_event_id
      }
      |> Outcome.changeset(%{
        title: proposal.title,
        description: proposal.description,
        motion: proposal.motion,
        success_measure: proposal.success_measure,
        baseline: proposal.baseline,
        target: proposal.target,
        target_date: proposal.target_date,
        metadata: proposal_metadata(proposal)
      })
      |> Repo.insert!()

    Search.index_account_outcome(outcome)
    audit_outcome("account_outcome.created", outcome, proposal, actor)
    approved = mark_approved!(proposal, actor, outcome.id)
    %{proposal: approved, outcome: outcome}
  end

  defp apply_and_approve(%OutcomeProposal{proposal_type: "outcome_review"} = proposal, actor) do
    outcome = Repo.get!(Outcome, proposal.outcome_id)

    if outcome.status != "active" do
      Repo.rollback(:outcome_not_active)
    end

    review =
      %OutcomeReview{outcome_id: outcome.id, author_id: actor && actor.id}
      |> OutcomeReview.changeset(%{
        health: proposal.health,
        summary: proposal.summary,
        evidence: proposal.evidence,
        recommendation: proposal.recommendation,
        reviewed_at: utc_now(),
        created_by_agent: proposal.generated_by_agent,
        metadata: proposal_metadata(proposal)
      })
      |> Repo.insert!()

    link_resolvable_evidence("account_outcome_review", review.id, proposal.evidence)

    updated_outcome =
      outcome
      |> Outcome.changeset(%{health: review.health, reviewed_at: review.reviewed_at})
      |> Repo.update!()

    Search.index_account_outcome(updated_outcome)
    audit_review("account_outcome.reviewed", review, proposal, actor)
    approved = mark_approved!(proposal, actor, outcome.id)
    %{proposal: approved, review: review, outcome: updated_outcome}
  end

  defp mark_approved!(proposal, actor, outcome_id) do
    proposal
    |> OutcomeProposal.decision_changeset(%{status: "approved", reviewed_at: utc_now()})
    |> Ecto.Changeset.put_change(:outcome_id, outcome_id)
    |> Ecto.Changeset.put_change(:reviewed_by_id, actor && actor.id)
    |> Repo.update!()
    |> tap(&audit_proposal("account_outcome_proposal.approved", &1, %{}, actor: actor))
  end

  defp mark_checked(account) do
    account
    |> Account.outcome_proposals_checked_changeset(%{outcome_proposals_checked_at: utc_now()})
    |> Repo.update()
  end

  defp generated_proposals(%{"proposals" => proposals}) when is_list(proposals), do: proposals
  defp generated_proposals(%{proposals: proposals}) when is_list(proposals), do: proposals
  defp generated_proposals(_result), do: []

  defp cast_confidence(%Decimal{} = confidence), do: {:ok, confidence}
  defp cast_confidence(confidence), do: Decimal.cast(confidence)

  defp validate_account_ownership(changeset, account) do
    outcome_id = Ecto.Changeset.get_field(changeset, :outcome_id)
    source_event_id = Ecto.Changeset.get_field(changeset, :source_event_id)
    evidence = Ecto.Changeset.get_field(changeset, :evidence)

    changeset
    |> validate_owned_outcome(account.id, outcome_id)
    |> validate_owned_source_event(account.id, source_event_id)
    |> validate_owned_evidence(account.id, evidence)
  end

  defp validate_owned_outcome(changeset, _account_id, nil), do: changeset

  defp validate_owned_outcome(changeset, account_id, outcome_id) do
    case Repo.get_by(Outcome, id: outcome_id, account_id: account_id) do
      %Outcome{status: "active"} -> changeset
      %Outcome{} -> Ecto.Changeset.add_error(changeset, :outcome_id, "must reference an active outcome")
      nil -> Ecto.Changeset.add_error(changeset, :outcome_id, "must belong to the account")
    end
  end

  defp validate_owned_source_event(changeset, _account_id, nil), do: changeset

  defp validate_owned_source_event(changeset, account_id, source_event_id) do
    if Repo.exists?(from(event in Event, where: event.id == ^source_event_id and event.account_id == ^account_id)) do
      changeset
    else
      Ecto.Changeset.add_error(changeset, :source_event_id, "must belong to the account")
    end
  end

  defp validate_owned_evidence(changeset, account_id, %{"items" => items}) when is_list(items) do
    evidence_ids =
      items
      |> Enum.map(fn item -> Map.get(item, "event_id") || Map.get(item, :event_id) end)
      |> Enum.reject(&is_nil/1)
      |> MapSet.new()

    owned_ids =
      Event
      |> where([event], event.account_id == ^account_id and event.id in ^MapSet.to_list(evidence_ids))
      |> select([event], event.id)
      |> Repo.all()
      |> MapSet.new()

    if MapSet.equal?(evidence_ids, owned_ids) do
      changeset
    else
      Ecto.Changeset.add_error(changeset, :evidence, "must reference events from the account")
    end
  end

  defp validate_owned_evidence(changeset, _account_id, _evidence), do: changeset

  defp first_evidence_event_id(%{"items" => [item | _rest]}) when is_map(item) do
    Map.get(item, "event_id") || Map.get(item, :event_id)
  end

  defp first_evidence_event_id(_evidence), do: nil

  defp link_evidence!(subject_type, subject_id, evidence) do
    case Evidence.link_all(subject_type, subject_id, evidence_records(evidence)) do
      {:ok, _links} -> :ok
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  # A proposal can outlive the account event it cited, through a deletion or a
  # re-sync that replaced the record. Approving it must not fail on that: the
  # review, the health update, and the approval itself matter more than a
  # pointer that no longer resolves, so the stale reference is dropped and
  # logged instead of rolling the decision back.
  defp link_resolvable_evidence(subject_type, subject_id, evidence) do
    case Evidence.link_resolvable(subject_type, subject_id, evidence_records(evidence)) do
      {:ok, _links, []} ->
        :ok

      {:ok, _links, unresolvable} ->
        Logger.warning(
          "Skipped #{length(unresolvable)} unresolvable evidence records while linking #{subject_type} #{subject_id}"
        )

        :ok

      {:error, reason} ->
        Repo.rollback(reason)
    end
  end

  defp evidence_records(%{"items" => items}) when is_list(items) do
    Enum.flat_map(items, fn item ->
      case Map.get(item, "event_id") || Map.get(item, :event_id) do
        id when is_binary(id) ->
          [
            %{
              record_type: "account_event",
              record_id: id,
              source_class: "observed",
              observation: Map.get(item, "observation") || Map.get(item, :observation) || "Account event"
            }
          ]

        _id ->
          []
      end
    end)
  end

  defp evidence_records(_evidence), do: []

  defp maybe_filter_statuses(query, nil), do: query
  defp maybe_filter_statuses(query, []), do: query
  defp maybe_filter_statuses(query, statuses), do: where(query, [proposal], proposal.status in ^statuses)

  defp proposal_metadata(proposal) do
    %{
      "proposal_id" => proposal.id,
      "proposal_confidence" => Decimal.to_string(proposal.confidence, :normal),
      "proposal_rationale" => proposal.rationale,
      "generated_by_agent" => proposal.generated_by_agent
    }
  end

  defp audit_proposal(action, proposal, metadata, opts \\ []) do
    Audit.record(
      action,
      %{
        target_type: "account_outcome_proposal",
        target_id: proposal.id,
        target_label: proposal.title || proposal.summary,
        metadata:
          Map.merge(metadata, %{
            "account_id" => proposal.account_id,
            "outcome_id" => proposal.outcome_id,
            "proposal_type" => proposal.proposal_type,
            "path" => "/sales/accounts/#{proposal.account_id}"
          })
      },
      opts
    )
  end

  defp audit_generation(account, proposals, considered_count) do
    Audit.record(
      "account_outcome_proposals.generated",
      %{
        target_type: "account",
        target_id: account.id,
        target_label: account.name,
        metadata: %{
          "created_count" => length(proposals),
          "discarded_count" => considered_count - length(proposals),
          "generated_by_agent" => @agent_name,
          "path" => "/sales/accounts/#{account.id}"
        }
      }
    )
  end

  defp audit_outcome(action, outcome, proposal, actor) do
    Audit.record(
      action,
      %{
        target_type: "account_outcome",
        target_id: outcome.id,
        target_label: outcome.title,
        metadata: %{
          "account_id" => outcome.account_id,
          "proposal_id" => proposal.id,
          "path" => "/sales/accounts/#{outcome.account_id}"
        }
      },
      actor: actor
    )
  end

  defp audit_review(action, review, proposal, actor) do
    Audit.record(
      action,
      %{
        target_type: "account_outcome_review",
        target_id: review.id,
        target_label: proposal.outcome && proposal.outcome.title,
        metadata: %{
          "account_id" => proposal.account_id,
          "outcome_id" => proposal.outcome_id,
          "proposal_id" => proposal.id,
          "path" => "/sales/accounts/#{proposal.account_id}"
        }
      },
      actor: actor
    )
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), value} end)
  end

  defp present?(value), do: is_binary(value) and String.trim(value) != ""
  defp utc_now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
