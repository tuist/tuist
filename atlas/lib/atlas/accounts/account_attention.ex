defmodule Atlas.Accounts.AccountAttention do
  @moduledoc """
  Generates, delivers, and remembers account follow-up suggestions.
  """

  import Ecto.Query

  alias Atlas.Accounts.Account
  alias Atlas.Accounts.AccountAttentionSlackNotifier
  alias Atlas.Accounts.AccountAttentionSuggestion
  alias Atlas.Accounts.Agents.AccountAttentionAgent
  alias Atlas.Accounts.Query
  alias Atlas.Audit
  alias Atlas.FeatureUsage
  alias Atlas.Repo

  @agent_name "account_attention_agent"
  @minimum_confidence Decimal.new("0.70")
  @dismissal_cooldown_days 28

  def list(account_or_id, opts \\ [])

  def list(%Account{id: account_id}, opts), do: list(account_id, opts)

  def list(account_id, opts) when is_binary(account_id) do
    statuses = Keyword.get(opts, :statuses)

    AccountAttentionSuggestion
    |> where([suggestion], suggestion.account_id == ^account_id)
    |> maybe_filter_statuses(statuses)
    |> order_by([suggestion], desc: suggestion.inserted_at)
    |> Repo.all()
  end

  def get(id) when is_binary(id), do: Repo.get(AccountAttentionSuggestion, id)

  def get(%Account{id: account_id}, id) when is_binary(id) do
    AccountAttentionSuggestion
    |> where([suggestion], suggestion.account_id == ^account_id)
    |> Repo.get(id)
  end

  def generate(account_id) when is_binary(account_id) do
    case Query.get_account(account_id) do
      nil ->
        {:error, :not_found}

      account ->
        usage = FeatureUsage.latest_usage_for_account(account.id)

        case AccountAttentionAgent.propose(account, usage) do
          {:ok, result} -> persist_generated(account, usage, result)
          {:error, reason} -> {:error, reason}
        end
    end
  end

  def mark_actioned(%AccountAttentionSuggestion{} = suggestion, note \\ nil) do
    resolve(suggestion, "actioned", %{resolution_note: note, resolved_at: utc_now()})
  end

  def dismiss(%AccountAttentionSuggestion{} = suggestion, note \\ nil) do
    resolve(suggestion, "dismissed", %{resolution_note: note, resolved_at: utc_now()})
  end

  def snooze(%AccountAttentionSuggestion{} = suggestion, until, note \\ nil) when is_struct(until, DateTime) do
    resolve(suggestion, "snoozed", %{snoozed_until: truncate(until), resolution_note: note})
  end

  def list_due_for_delivery(now \\ utc_now()) do
    AccountAttentionSuggestion
    |> where([suggestion], suggestion.status == "pending" and is_nil(suggestion.posted_at))
    |> or_where(
      [suggestion],
      suggestion.status == "snoozed" and not is_nil(suggestion.snoozed_until) and
        suggestion.snoozed_until <= ^now
    )
    |> order_by([suggestion], asc: suggestion.inserted_at)
    |> preload(:account)
    |> Repo.all()
  end

  def record_delivery(%AccountAttentionSuggestion{} = suggestion, attrs) when is_map(attrs) do
    attrs =
      if suggestion.status == "snoozed" do
        attrs |> Map.put(:status, "pending") |> Map.put(:snoozed_until, nil)
      else
        attrs
      end

    suggestion
    |> AccountAttentionSuggestion.delivery_changeset(attrs)
    |> Repo.update()
    |> tap(fn
      {:ok, delivered} -> audit("account_attention_suggestion.delivered", delivered, %{})
      _result -> :ok
    end)
  end

  def deliver(%AccountAttentionSuggestion{} = suggestion) do
    suggestion = Repo.preload(suggestion, :account)

    with {:ok, delivery} <- AccountAttentionSlackNotifier.notify(suggestion) do
      record_delivery(suggestion, delivery)
    end
  end

  def mark_checked(%Account{} = account, checked_at \\ utc_now()) do
    account
    |> Account.attention_suggestions_checked_changeset(%{
      attention_suggestions_checked_at: truncate(checked_at)
    })
    |> Repo.update()
  end

  defp persist_generated(account, usage, result) do
    created =
      result
      |> generated_suggestions()
      |> Enum.take(3)
      |> Enum.flat_map(fn raw ->
        case normalize_generated(account, usage, raw) do
          {:ok, attrs} ->
            case create_if_eligible(account, attrs) do
              {:ok, suggestion} -> [suggestion]
              :skip -> []
              {:error, _changeset} -> []
            end

          :skip ->
            []
        end
      end)

    {:ok, _account} = mark_checked(account)
    audit_generation(account, created)
    {:ok, created}
  end

  defp generated_suggestions(%{"suggestions" => suggestions}) when is_list(suggestions), do: suggestions
  defp generated_suggestions(%{suggestions: suggestions}) when is_list(suggestions), do: suggestions
  defp generated_suggestions(_result), do: []

  defp normalize_generated(account, usage, raw) when is_map(raw) do
    raw = stringify_keys(raw)
    kind = raw["kind"]
    topic = raw["topic"]
    evidence = valid_evidence(account, usage, raw["evidence"])

    with {:ok, confidence} <- cast_confidence(raw["confidence"]),
         true <- Decimal.compare(confidence, @minimum_confidence) in [:eq, :gt],
         true <- kind in AccountAttentionSuggestion.kinds(),
         true <- present?(topic),
         true <- present?(raw["title"]),
         true <- present?(raw["rationale"]),
         true <- present?(raw["suggested_action"]),
         true <- evidence != [] do
      {:ok,
       %{
         status: "pending",
         kind: kind,
         suggestion_key: AccountAttentionSuggestion.suggestion_key(kind, topic),
         title: raw["title"],
         rationale: raw["rationale"],
         suggested_action: raw["suggested_action"],
         evidence: %{"items" => evidence},
         confidence: confidence,
         generated_by_agent: @agent_name
       }}
    else
      _reason -> :skip
    end
  end

  defp normalize_generated(_account, _usage, _raw), do: :skip

  defp valid_evidence(account, usage, evidence) when is_list(evidence) do
    event_ids = MapSet.new(account.events, & &1.id)
    usage_ids = MapSet.new(usage, & &1.id)

    evidence
    |> Enum.map(&stringify_keys/1)
    |> Enum.filter(fn item ->
      present?(item["observation"]) and
        case {item["source_type"], item["source_id"]} do
          {"account", account_id} -> account_id == account.id
          {"account_event", event_id} -> MapSet.member?(event_ids, event_id)
          {"feature_usage_snapshot", snapshot_id} -> MapSet.member?(usage_ids, snapshot_id)
          _source -> false
        end
    end)
    |> Enum.uniq_by(fn item -> {item["source_type"], item["source_id"]} end)
  end

  defp valid_evidence(_account, _usage, _evidence), do: []

  defp create_if_eligible(account, attrs) do
    if eligible?(account, attrs) do
      %AccountAttentionSuggestion{account_id: account.id}
      |> AccountAttentionSuggestion.changeset(attrs)
      |> Repo.insert()
      |> tap(fn
        {:ok, suggestion} -> audit("account_attention_suggestion.created", suggestion, %{})
        _result -> :ok
      end)
    else
      :skip
    end
  end

  defp eligible?(account, attrs) do
    key = attrs.suggestion_key

    case Enum.find(account.attention_suggestions, &(&1.suggestion_key == key)) do
      nil ->
        true

      %{status: status} when status in ["pending", "snoozed"] ->
        false

      %{status: "dismissed", resolved_at: resolved_at} ->
        resolved_at && DateTime.before?(resolved_at, DateTime.add(utc_now(), -@dismissal_cooldown_days, :day))

      %{status: "actioned"} ->
        has_new_evidence?(account, key, attrs.evidence)

      _suggestion ->
        false
    end
  end

  defp has_new_evidence?(account, key, evidence) do
    current_sources = evidence_sources(evidence)

    account.attention_suggestions
    |> Enum.filter(&(&1.suggestion_key == key))
    |> Enum.flat_map(&evidence_sources(&1.evidence))
    |> MapSet.new()
    |> then(fn previous_sources -> not MapSet.subset?(current_sources, previous_sources) end)
  end

  defp evidence_sources(%{"items" => items}) when is_list(items) do
    items
    |> Enum.map(&stringify_keys/1)
    |> MapSet.new(fn item -> {item["source_type"], item["source_id"]} end)
  end

  defp evidence_sources(_evidence), do: MapSet.new()

  defp resolve(suggestion, status, attrs) do
    attrs = Map.put(attrs, :status, status)

    suggestion
    |> AccountAttentionSuggestion.resolution_changeset(attrs)
    |> Repo.update()
    |> tap(fn
      {:ok, resolved} -> audit("account_attention_suggestion.#{status}", resolved, %{})
      _result -> :ok
    end)
  end

  defp audit_generation(account, suggestions) do
    Audit.record("account_attention_suggestions.generated", %{
      target_type: "account",
      target_id: account.id,
      target_label: account.name,
      metadata: %{
        "path" => "/commercial/sales/accounts/#{account.id}",
        "suggestion_count" => length(suggestions)
      }
    })
  end

  defp audit(action, suggestion, metadata) do
    Audit.record(action, %{
      target_type: "account_attention_suggestion",
      target_id: suggestion.id,
      target_label: suggestion.title,
      metadata:
        Map.merge(
          %{
            "account_id" => suggestion.account_id,
            "path" => "/commercial/sales/accounts/#{suggestion.account_id}",
            "status" => suggestion.status
          },
          metadata
        )
    })
  end

  defp maybe_filter_statuses(query, nil), do: query
  defp maybe_filter_statuses(query, []), do: query
  defp maybe_filter_statuses(query, statuses), do: where(query, [suggestion], suggestion.status in ^statuses)

  defp cast_confidence(%Decimal{} = confidence), do: {:ok, confidence}

  defp cast_confidence(value) when is_binary(value) do
    case Decimal.parse(value) do
      {confidence, ""} -> {:ok, confidence}
      _result -> :error
    end
  end

  defp cast_confidence(value) when is_float(value) or is_integer(value), do: {:ok, Decimal.new(to_string(value))}
  defp cast_confidence(_value), do: :error

  defp stringify_keys(map) when is_map(map), do: Map.new(map, fn {key, value} -> {to_string(key), value} end)
  defp stringify_keys(value), do: value

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_value), do: false

  defp utc_now, do: DateTime.utc_now() |> DateTime.truncate(:second)
  defp truncate(datetime), do: DateTime.truncate(datetime, :second)
end
