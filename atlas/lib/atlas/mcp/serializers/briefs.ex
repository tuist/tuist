defmodule Atlas.MCP.Serializers.Briefs do
  @moduledoc false

  alias Atlas.Briefs.Brief
  alias Atlas.Briefs.BriefItem
  alias Atlas.Coordination.CrossDomainClaim
  alias Atlas.Evidence
  alias Atlas.MCP.Tool
  alias Atlas.Product.Trace

  def brief(%Brief{} = brief, opts \\ []) do
    include_items = Keyword.get(opts, :include_items, false)

    %{
      id: brief.id,
      cadence: brief.cadence,
      status: brief.status,
      headline: brief.headline,
      summary: brief.summary,
      period_start: Tool.iso8601(brief.period_start),
      period_end: Tool.iso8601(brief.period_end),
      sensitivity: brief.sensitivity,
      audience: brief.subscription.audience_key,
      domains: brief.subscription.domains,
      posted_at: Tool.iso8601(brief.posted_at),
      slack_channel_id: brief.slack_channel_id,
      slack_thread_ts: brief.slack_thread_ts,
      items: if(include_items, do: Enum.map(brief.items, &brief_item(&1, include_evidence: true)), else: [])
    }
  end

  def brief_item(%BriefItem{} = item, opts \\ []) do
    include_evidence = Keyword.get(opts, :include_evidence, false)

    %{
      id: item.id,
      brief_id: item.brief_id,
      domain: item.domain,
      kind: item.kind,
      title: item.title,
      detail: item.detail,
      severity: item.severity,
      sensitivity: item.sensitivity,
      materiality_score: decimal(item.materiality_score),
      confidence: decimal(item.confidence),
      suggested_action: item.suggested_action,
      completion_condition: item.completion_condition,
      status: item.status,
      owner_id: item.owner_id,
      due_at: Tool.iso8601(item.due_at),
      resolved_at: Tool.iso8601(item.resolved_at),
      resolution_note: item.resolution_note,
      usefulness: item.usefulness,
      source_type: item.source_type,
      source_id: item.source_id,
      source_path: item.source_path,
      evidence: if(include_evidence, do: evidence(item), else: [])
    }
  end

  def product_trace(%Trace{} = trace) do
    %{
      id: trace.id,
      kind: trace.kind,
      repository: trace.repository_full_name,
      number: trace.number,
      title: trace.title,
      url: trace.url,
      author_login: trace.author_login,
      occurred_at: Tool.iso8601(trace.occurred_at),
      labels: trace.labels,
      sensitivity: trace.sensitivity
    }
  end

  def claim(%CrossDomainClaim{} = claim) do
    %{
      id: claim.id,
      claim_kind: claim.claim_kind,
      domains: claim.domains,
      account_id: claim.subject_account_id,
      account_name: claim.subject_account && claim.subject_account.name,
      version: claim.version,
      statement: claim.statement,
      confidence: decimal(claim.confidence),
      sensitivity: claim.sensitivity,
      link_precision: claim.link_precision,
      link_basis: claim.link_basis,
      generated_by_agent: claim.generated_by_agent,
      valid_from: Tool.iso8601(claim.valid_from),
      valid_until: Tool.iso8601(claim.valid_until)
    }
  end

  def brief_schema do
    %{
      "type" => "object",
      "properties" => %{
        "id" => %{"type" => "string"},
        "cadence" => %{"type" => "string"},
        "status" => %{"type" => "string"},
        "headline" => %{"type" => ["string", "null"]},
        "summary" => %{"type" => ["string", "null"]},
        "period_start" => %{"type" => "string"},
        "period_end" => %{"type" => "string"},
        "sensitivity" => %{"type" => "string"},
        "audience" => %{"type" => "string"},
        "domains" => %{"type" => "array", "items" => %{"type" => "string"}},
        "posted_at" => %{"type" => ["string", "null"]},
        "slack_channel_id" => %{"type" => ["string", "null"]},
        "slack_thread_ts" => %{"type" => ["string", "null"]},
        "items" => %{"type" => "array", "items" => brief_item_schema()}
      },
      "required" => [
        "id",
        "cadence",
        "status",
        "headline",
        "summary",
        "period_start",
        "period_end",
        "sensitivity",
        "audience",
        "domains",
        "posted_at",
        "slack_channel_id",
        "slack_thread_ts",
        "items"
      ],
      "additionalProperties" => false
    }
  end

  def brief_item_schema do
    %{
      "type" => "object",
      "properties" => %{
        "id" => %{"type" => "string"},
        "brief_id" => %{"type" => "string"},
        "domain" => %{"type" => "string"},
        "kind" => %{"type" => "string"},
        "title" => %{"type" => "string"},
        "detail" => %{"type" => "string"},
        "severity" => %{"type" => "string"},
        "sensitivity" => %{"type" => "string"},
        "materiality_score" => %{"type" => ["string", "null"]},
        "confidence" => %{"type" => ["string", "null"]},
        "suggested_action" => %{"type" => ["string", "null"]},
        "completion_condition" => %{"type" => ["string", "null"]},
        "status" => %{"type" => "string"},
        "owner_id" => %{"type" => ["string", "null"]},
        "due_at" => %{"type" => ["string", "null"]},
        "resolved_at" => %{"type" => ["string", "null"]},
        "resolution_note" => %{"type" => ["string", "null"]},
        "usefulness" => %{"type" => ["string", "null"]},
        "source_type" => %{"type" => ["string", "null"]},
        "source_id" => %{"type" => ["string", "null"]},
        "source_path" => %{"type" => ["string", "null"]},
        "evidence" => %{"type" => "array", "items" => evidence_schema()}
      },
      "required" => [
        "id",
        "brief_id",
        "domain",
        "kind",
        "title",
        "detail",
        "severity",
        "sensitivity",
        "materiality_score",
        "confidence",
        "suggested_action",
        "completion_condition",
        "status",
        "owner_id",
        "due_at",
        "resolved_at",
        "resolution_note",
        "usefulness",
        "source_type",
        "source_id",
        "source_path",
        "evidence"
      ],
      "additionalProperties" => false
    }
  end

  def product_trace_schema do
    %{
      "type" => "object",
      "properties" => %{
        "id" => %{"type" => "string"},
        "kind" => %{"type" => "string"},
        "repository" => %{"type" => "string"},
        "number" => %{"type" => "integer"},
        "title" => %{"type" => "string"},
        "url" => %{"type" => "string"},
        "author_login" => %{"type" => ["string", "null"]},
        "occurred_at" => %{"type" => "string"},
        "labels" => %{"type" => "array", "items" => %{"type" => "string"}},
        "sensitivity" => %{"type" => "string"}
      },
      "required" => [
        "id",
        "kind",
        "repository",
        "number",
        "title",
        "url",
        "author_login",
        "occurred_at",
        "labels",
        "sensitivity"
      ],
      "additionalProperties" => false
    }
  end

  def claim_schema do
    %{
      "type" => "object",
      "properties" => %{
        "id" => %{"type" => "string"},
        "claim_kind" => %{"type" => "string"},
        "domains" => %{"type" => "array", "items" => %{"type" => "string"}},
        "account_id" => %{"type" => "string"},
        "account_name" => %{"type" => ["string", "null"]},
        "version" => %{"type" => "integer"},
        "statement" => %{"type" => "string"},
        "confidence" => %{"type" => ["string", "null"]},
        "sensitivity" => %{"type" => "string"},
        "link_precision" => %{"type" => "string"},
        "link_basis" => %{"type" => "string"},
        "generated_by_agent" => %{"type" => "string"},
        "valid_from" => %{"type" => "string"},
        "valid_until" => %{"type" => ["string", "null"]}
      },
      "required" => [
        "id",
        "claim_kind",
        "domains",
        "account_id",
        "account_name",
        "version",
        "statement",
        "confidence",
        "sensitivity",
        "link_precision",
        "link_basis",
        "generated_by_agent",
        "valid_from",
        "valid_until"
      ],
      "additionalProperties" => false
    }
  end

  defp evidence(item) do
    "brief_item"
    |> Evidence.for_subject(item.id)
    |> Enum.map(fn link ->
      %{
        record_type: link.record_type,
        record_id: link.record_id,
        source_class: link.source_class,
        sensitivity: link.sensitivity,
        observation: link.observation,
        occurred_at: Tool.iso8601(link.occurred_at)
      }
    end)
  end

  defp evidence_schema do
    %{
      "type" => "object",
      "properties" => %{
        "record_type" => %{"type" => "string"},
        "record_id" => %{"type" => "string"},
        "source_class" => %{"type" => "string"},
        "sensitivity" => %{"type" => "string"},
        "observation" => %{"type" => "string"},
        "occurred_at" => %{"type" => "string"}
      },
      "required" => [
        "record_type",
        "record_id",
        "source_class",
        "sensitivity",
        "observation",
        "occurred_at"
      ],
      "additionalProperties" => false
    }
  end

  defp decimal(nil), do: nil
  defp decimal(%Decimal{} = value), do: Decimal.to_string(value, :normal)
end
