defmodule Atlas.MCP.Serializers.Accounts do
  @moduledoc false

  alias Atlas.Accounts, as: AccountContext
  alias Atlas.Accounts.Account.Address
  alias Atlas.Accounts.Account.Billing
  alias Atlas.Accounts.Account.Signatory
  alias Atlas.Accounts.IncidentContact
  alias Atlas.Documents.Document
  alias Atlas.MCP.Tool

  def list_response(key, items), do: %{key => items, count: length(items)}

  defp loaded_collection(%Ecto.Association.NotLoaded{}), do: []
  defp loaded_collection(items) when is_list(items), do: items
  defp loaded_collection(_items), do: []

  def list_response_schema(key, item_schema) do
    %{
      "type" => "object",
      "properties" => %{
        to_string(key) => %{"type" => "array", "items" => item_schema},
        "count" => %{"type" => "integer"}
      },
      "required" => [to_string(key), "count"],
      "additionalProperties" => false
    }
  end

  def account(account) do
    {current_value, currency} = AccountContext.contract_value(account)

    %{
      id: account.id,
      account_key: account.account_key,
      name: account.name,
      legal_name: account.legal_name,
      contract_id: account.contract_id,
      description: account.description,
      attention_context: account.attention_context,
      primary_domain: account.primary_domain,
      address: address(account.address),
      billing: billing(account.billing),
      signatory: signatory(account.signatory),
      parent_account_id: account.parent_account_id,
      parent_account: related_account(account.parent_account),
      child_accounts: Enum.map(account.child_accounts, &related_account/1),
      url: account.url,
      status: account.status,
      segment: account.segment,
      hosting: account.hosting,
      deal_stage: account.deal_stage,
      currency: currency,
      current_value: current_value && Decimal.to_string(current_value),
      next_renewal_date: Tool.iso8601(account.next_renewal_date),
      overview_summary: account.overview_summary,
      not_an_account_at: Tool.iso8601(account.not_an_account_at),
      not_an_account_reason: account.not_an_account_reason,
      latest_activity_at: Tool.iso8601(account.latest_activity_at)
    }
  end

  def account_schema do
    %{
      "type" => "object",
      "properties" => %{
        "id" => %{"type" => "string"},
        "account_key" => %{"type" => "string"},
        "name" => %{"type" => ["string", "null"]},
        "legal_name" => %{"type" => ["string", "null"]},
        "contract_id" => %{"type" => ["string", "null"]},
        "description" => %{"type" => ["string", "null"]},
        "attention_context" => %{"type" => ["string", "null"]},
        "primary_domain" => %{"type" => ["string", "null"]},
        "address" => Tool.nullable(address_schema()),
        "billing" => Tool.nullable(billing_schema()),
        "signatory" => Tool.nullable(signatory_schema()),
        "parent_account_id" => %{"type" => ["string", "null"]},
        "parent_account" => Tool.nullable(related_account_schema()),
        "child_accounts" => %{"type" => "array", "items" => related_account_schema()},
        "url" => %{"type" => ["string", "null"]},
        "status" => %{"type" => ["string", "null"]},
        "segment" => %{"type" => ["string", "null"]},
        "hosting" => %{"type" => ["string", "null"]},
        "deal_stage" => %{"type" => ["string", "null"]},
        "currency" => %{"type" => ["string", "null"]},
        "current_value" => %{"type" => ["string", "null"]},
        "next_renewal_date" => %{"type" => ["string", "null"]},
        "overview_summary" => %{"type" => ["string", "null"]},
        "not_an_account_at" => %{"type" => ["string", "null"]},
        "not_an_account_reason" => %{"type" => ["string", "null"]},
        "latest_activity_at" => %{"type" => ["string", "null"]}
      },
      "required" => [
        "id",
        "account_key",
        "name",
        "legal_name",
        "contract_id",
        "description",
        "attention_context",
        "primary_domain",
        "address",
        "billing",
        "signatory",
        "parent_account_id",
        "parent_account",
        "child_accounts",
        "url",
        "status",
        "segment",
        "hosting",
        "deal_stage",
        "currency",
        "current_value",
        "next_renewal_date",
        "overview_summary",
        "not_an_account_at",
        "not_an_account_reason",
        "latest_activity_at"
      ],
      "additionalProperties" => false
    }
  end

  def address(nil), do: nil

  def address(%Address{} = address) do
    %{
      street: address.street,
      city: address.city,
      zip: address.zip,
      country: address.country
    }
  end

  def address_schema do
    nullable_string = %{"type" => ["string", "null"]}

    %{
      "type" => "object",
      "properties" => %{
        "street" => nullable_string,
        "city" => nullable_string,
        "zip" => nullable_string,
        "country" => nullable_string
      },
      "required" => ["street", "city", "zip", "country"],
      "additionalProperties" => false
    }
  end

  def billing(nil), do: nil

  def billing(%Billing{} = billing) do
    %{
      tax_id: billing.tax_id,
      vat_id: billing.vat_id,
      sold_to: billing.sold_to,
      bill_to: billing.bill_to,
      email: billing.email,
      phone: billing.phone
    }
  end

  def billing_schema do
    nullable_string = %{"type" => ["string", "null"]}

    %{
      "type" => "object",
      "properties" => %{
        "tax_id" => nullable_string,
        "vat_id" => nullable_string,
        "sold_to" => nullable_string,
        "bill_to" => nullable_string,
        "email" => nullable_string,
        "phone" => nullable_string
      },
      "required" => ["tax_id", "vat_id", "sold_to", "bill_to", "email", "phone"],
      "additionalProperties" => false
    }
  end

  def signatory(nil), do: nil

  def signatory(%Signatory{} = signatory) do
    %{
      name: signatory.name,
      title: signatory.title
    }
  end

  def signatory_schema do
    %{
      "type" => "object",
      "properties" => %{
        "name" => %{"type" => ["string", "null"]},
        "title" => %{"type" => ["string", "null"]}
      },
      "required" => ["name", "title"],
      "additionalProperties" => false
    }
  end

  def related_account(nil), do: nil

  def related_account(account) do
    %{
      id: account.id,
      account_key: account.account_key,
      name: account.name,
      primary_domain: account.primary_domain,
      segment: account.segment
    }
  end

  def related_account_schema do
    %{
      "type" => "object",
      "properties" => %{
        "id" => %{"type" => "string"},
        "account_key" => %{"type" => "string"},
        "name" => %{"type" => ["string", "null"]},
        "primary_domain" => %{"type" => ["string", "null"]},
        "segment" => %{"type" => ["string", "null"]}
      },
      "required" => ["id", "account_key", "name", "primary_domain", "segment"],
      "additionalProperties" => false
    }
  end

  def contact(contact) do
    %{
      id: contact.id,
      account_id: Map.get(contact, :account_id),
      full_name: contact.full_name,
      email: contact.email,
      title: contact.title,
      notes: Map.get(contact, :notes),
      linkedin_url: Map.get(contact, :linkedin_url),
      source: Map.get(contact, :source),
      outreach_status: Map.get(contact, :outreach_status),
      outreach_enrolled_at: Tool.iso8601(Map.get(contact, :outreach_enrolled_at)),
      last_outreach_at: Tool.iso8601(Map.get(contact, :last_outreach_at))
    }
  end

  def contact_schema do
    %{
      "type" => "object",
      "properties" => %{
        "id" => %{"type" => "string"},
        "account_id" => %{"type" => ["string", "null"]},
        "full_name" => %{"type" => ["string", "null"]},
        "email" => %{"type" => ["string", "null"]},
        "title" => %{"type" => ["string", "null"]},
        "notes" => %{"type" => ["string", "null"]},
        "linkedin_url" => %{"type" => ["string", "null"]},
        "source" => %{"type" => ["string", "null"]},
        "outreach_status" => %{"type" => ["string", "null"]},
        "outreach_enrolled_at" => %{"type" => ["string", "null"]},
        "last_outreach_at" => %{"type" => ["string", "null"]}
      },
      "required" => [
        "id",
        "account_id",
        "full_name",
        "email",
        "title",
        "notes",
        "linkedin_url",
        "source",
        "outreach_status",
        "outreach_enrolled_at",
        "last_outreach_at"
      ],
      "additionalProperties" => false
    }
  end

  def handle(handle), do: %{handle: handle.handle, source: handle.source}

  def handle_schema do
    %{
      "type" => "object",
      "properties" => %{
        "handle" => %{"type" => "string"},
        "source" => %{"type" => "string"}
      },
      "required" => ["handle", "source"],
      "additionalProperties" => false
    }
  end

  def event(event) do
    %{
      id: event.id,
      contact_id: event.contact_id,
      source: event.source,
      kind: event.kind,
      title: event.title,
      occurred_at: Tool.iso8601(event.occurred_at),
      url: event.url,
      author_email: author_email(event)
    }
  end

  def event_schema do
    %{
      "type" => "object",
      "properties" => %{
        "id" => %{"type" => "string"},
        "contact_id" => %{"type" => ["string", "null"]},
        "source" => %{"type" => "string"},
        "kind" => %{"type" => "string"},
        "title" => %{"type" => ["string", "null"]},
        "occurred_at" => %{"type" => ["string", "null"]},
        "url" => %{"type" => ["string", "null"]},
        "author_email" => %{"type" => ["string", "null"]}
      },
      "required" => ["id", "contact_id", "source", "kind", "title", "occurred_at", "url", "author_email"],
      "additionalProperties" => false
    }
  end

  def full_event(event) do
    event
    |> event()
    |> Map.merge(%{
      account_id: event.account_id,
      body: event.body,
      metadata: event.metadata
    })
  end

  def full_event_schema do
    base = event_schema()

    %{
      base
      | "properties" =>
          Map.merge(base["properties"], %{
            "account_id" => %{"type" => ["string", "null"]},
            "body" => %{"type" => ["string", "null"]},
            "metadata" => %{"type" => ["object", "null"]}
          }),
        "required" => base["required"] ++ ["account_id", "body", "metadata"]
    }
  end

  def outcome(outcome) do
    %{
      id: outcome.id,
      account_id: outcome.account_id,
      title: outcome.title,
      description: outcome.description,
      status: outcome.status,
      health: outcome.health,
      motion: outcome.motion,
      success_measure: outcome.success_measure,
      baseline: outcome.baseline,
      target: outcome.target,
      target_date: Tool.iso8601(outcome.target_date),
      reviewed_at: Tool.iso8601(outcome.reviewed_at),
      achieved_at: Tool.iso8601(outcome.achieved_at),
      reviews: Enum.map(loaded_collection(outcome.reviews), &outcome_review/1)
    }
  end

  def outcome_schema do
    %{
      "type" => "object",
      "properties" => %{
        "id" => %{"type" => "string"},
        "account_id" => %{"type" => "string"},
        "title" => %{"type" => ["string", "null"]},
        "description" => %{"type" => ["string", "null"]},
        "status" => %{"type" => ["string", "null"]},
        "health" => %{"type" => ["string", "null"]},
        "motion" => %{"type" => ["string", "null"]},
        "success_measure" => %{"type" => ["string", "null"]},
        "baseline" => %{"type" => ["string", "null"]},
        "target" => %{"type" => ["string", "null"]},
        "target_date" => %{"type" => ["string", "null"]},
        "reviewed_at" => %{"type" => ["string", "null"]},
        "achieved_at" => %{"type" => ["string", "null"]},
        "reviews" => %{"type" => "array", "items" => outcome_review_schema()}
      },
      "required" => [
        "id",
        "account_id",
        "title",
        "description",
        "status",
        "health",
        "motion",
        "success_measure",
        "baseline",
        "target",
        "target_date",
        "reviewed_at",
        "achieved_at",
        "reviews"
      ],
      "additionalProperties" => false
    }
  end

  def outcome_review(review) do
    %{
      id: review.id,
      health: review.health,
      summary: review.summary,
      evidence: review.evidence,
      recommendation: review.recommendation,
      reviewed_at: Tool.iso8601(review.reviewed_at),
      created_by_agent: review.created_by_agent
    }
  end

  def outcome_review_schema do
    %{
      "type" => "object",
      "properties" => %{
        "id" => %{"type" => "string"},
        "health" => %{"type" => "string"},
        "summary" => %{"type" => "string"},
        "evidence" => %{"type" => "object"},
        "recommendation" => %{"type" => ["string", "null"]},
        "reviewed_at" => %{"type" => "string"},
        "created_by_agent" => %{"type" => ["string", "null"]}
      },
      "required" => [
        "id",
        "health",
        "summary",
        "evidence",
        "recommendation",
        "reviewed_at",
        "created_by_agent"
      ],
      "additionalProperties" => false
    }
  end

  def outcome_proposal(proposal) do
    %{
      id: proposal.id,
      account_id: proposal.account_id,
      outcome_id: proposal.outcome_id,
      outcome_title: related_outcome_title(proposal),
      proposal_type: proposal.proposal_type,
      status: proposal.status,
      title: proposal.title,
      description: proposal.description,
      motion: proposal.motion,
      success_measure: proposal.success_measure,
      baseline: proposal.baseline,
      target: proposal.target,
      target_date: Tool.iso8601(proposal.target_date),
      health: proposal.health,
      summary: proposal.summary,
      recommendation: proposal.recommendation,
      evidence: proposal.evidence,
      confidence: decimal_string(proposal.confidence),
      rationale: proposal.rationale,
      generated_by_agent: proposal.generated_by_agent,
      rejection_reason: proposal.rejection_reason,
      reviewed_at: Tool.iso8601(proposal.reviewed_at),
      inserted_at: Tool.iso8601(proposal.inserted_at)
    }
  end

  def outcome_proposal_schema do
    nullable_string = %{"type" => ["string", "null"]}

    %{
      "type" => "object",
      "properties" => %{
        "id" => %{"type" => "string"},
        "account_id" => %{"type" => "string"},
        "outcome_id" => nullable_string,
        "outcome_title" => nullable_string,
        "proposal_type" => %{"type" => "string"},
        "status" => %{"type" => "string"},
        "title" => nullable_string,
        "description" => nullable_string,
        "motion" => nullable_string,
        "success_measure" => nullable_string,
        "baseline" => nullable_string,
        "target" => nullable_string,
        "target_date" => nullable_string,
        "health" => nullable_string,
        "summary" => nullable_string,
        "recommendation" => nullable_string,
        "evidence" => %{"type" => "object"},
        "confidence" => %{"type" => "string"},
        "rationale" => %{"type" => "string"},
        "generated_by_agent" => %{"type" => "string"},
        "rejection_reason" => nullable_string,
        "reviewed_at" => nullable_string,
        "inserted_at" => %{"type" => ["string", "null"]}
      },
      "required" => [
        "id",
        "account_id",
        "outcome_id",
        "outcome_title",
        "proposal_type",
        "status",
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
        "evidence",
        "confidence",
        "rationale",
        "generated_by_agent",
        "rejection_reason",
        "reviewed_at",
        "inserted_at"
      ],
      "additionalProperties" => false
    }
  end

  def account_attention_suggestion(suggestion) do
    %{
      id: suggestion.id,
      account_id: suggestion.account_id,
      status: suggestion.status,
      kind: suggestion.kind,
      title: suggestion.title,
      rationale: suggestion.rationale,
      suggested_action: suggestion.suggested_action,
      evidence: suggestion.evidence,
      confidence: decimal_string(suggestion.confidence),
      snoozed_until: Tool.iso8601(suggestion.snoozed_until),
      resolved_at: Tool.iso8601(suggestion.resolved_at),
      resolution_note: suggestion.resolution_note,
      posted_at: Tool.iso8601(suggestion.posted_at),
      inserted_at: Tool.iso8601(suggestion.inserted_at)
    }
  end

  def account_attention_suggestion_schema do
    nullable_string = %{"type" => ["string", "null"]}

    %{
      "type" => "object",
      "properties" => %{
        "id" => %{"type" => "string"},
        "account_id" => %{"type" => "string"},
        "status" => %{"type" => "string"},
        "kind" => %{"type" => "string"},
        "title" => %{"type" => "string"},
        "rationale" => %{"type" => "string"},
        "suggested_action" => %{"type" => "string"},
        "evidence" => %{"type" => "object"},
        "confidence" => %{"type" => "string"},
        "snoozed_until" => nullable_string,
        "resolved_at" => nullable_string,
        "resolution_note" => nullable_string,
        "posted_at" => nullable_string,
        "inserted_at" => nullable_string
      },
      "required" => [
        "id",
        "account_id",
        "status",
        "kind",
        "title",
        "rationale",
        "suggested_action",
        "evidence",
        "confidence",
        "snoozed_until",
        "resolved_at",
        "resolution_note",
        "posted_at",
        "inserted_at"
      ],
      "additionalProperties" => false
    }
  end

  def service_level(service_level) do
    %{
      id: service_level.id,
      account_id: service_level.account_id,
      document_id: service_level.document_id,
      document_title: service_level.document && service_level.document.title,
      document_url: document_url(service_level.document, service_level.document_id),
      extraction_check_id: service_level.service_level_extraction_check_id,
      name: service_level.name,
      category: service_level.category,
      target: service_level.target,
      target_value: decimal_string(service_level.target_value),
      target_unit: service_level.target_unit,
      measurement_window: service_level.measurement_window,
      applies_from: Tool.iso8601(service_level.applies_from),
      applies_until: Tool.iso8601(service_level.applies_until),
      service_credit: service_level.service_credit,
      exclusions: service_level.exclusions,
      source_page: service_level.source_page,
      source_excerpt: service_level.source_excerpt,
      confidence: decimal_string(service_level.confidence),
      metadata: service_level.metadata
    }
  end

  def service_level_schema do
    %{
      "type" => "object",
      "properties" => %{
        "id" => %{"type" => "string"},
        "account_id" => %{"type" => ["string", "null"]},
        "document_id" => %{"type" => ["string", "null"]},
        "document_title" => %{"type" => ["string", "null"]},
        "document_url" => %{"type" => ["string", "null"]},
        "extraction_check_id" => %{"type" => ["string", "null"]},
        "name" => %{"type" => ["string", "null"]},
        "category" => %{"type" => ["string", "null"]},
        "target" => %{"type" => ["string", "null"]},
        "target_value" => %{"type" => ["string", "null"]},
        "target_unit" => %{"type" => ["string", "null"]},
        "measurement_window" => %{"type" => ["string", "null"]},
        "applies_from" => %{"type" => ["string", "null"]},
        "applies_until" => %{"type" => ["string", "null"]},
        "service_credit" => %{"type" => ["string", "null"]},
        "exclusions" => %{"type" => ["string", "null"]},
        "source_page" => %{"type" => ["integer", "null"]},
        "source_excerpt" => %{"type" => ["string", "null"]},
        "confidence" => %{"type" => ["string", "null"]},
        "metadata" => %{"type" => ["object", "null"]}
      },
      "required" => [
        "id",
        "account_id",
        "document_id",
        "document_title",
        "document_url",
        "extraction_check_id",
        "name",
        "category",
        "target",
        "target_value",
        "target_unit",
        "measurement_window",
        "applies_from",
        "applies_until",
        "service_credit",
        "exclusions",
        "source_page",
        "source_excerpt",
        "confidence",
        "metadata"
      ],
      "additionalProperties" => false
    }
  end

  def service_level_extraction_check(check) do
    %{
      id: check.id,
      account_id: check.account_id,
      document_id: check.document_id,
      document_title: check.document && check.document.title,
      document_url: document_url(check.document, check.document_id),
      agent_version: check.agent_version,
      status: check.status,
      started_at: Tool.iso8601(check.started_at),
      completed_at: Tool.iso8601(check.completed_at),
      result_summary: check.result_summary,
      last_error: check.last_error
    }
  end

  def service_level_extraction_check_schema do
    %{
      "type" => "object",
      "properties" => %{
        "id" => %{"type" => "string"},
        "account_id" => %{"type" => ["string", "null"]},
        "document_id" => %{"type" => ["string", "null"]},
        "document_title" => %{"type" => ["string", "null"]},
        "document_url" => %{"type" => ["string", "null"]},
        "agent_version" => %{"type" => ["string", "null"]},
        "status" => %{"type" => ["string", "null"]},
        "started_at" => %{"type" => ["string", "null"]},
        "completed_at" => %{"type" => ["string", "null"]},
        "result_summary" => %{"type" => ["string", "null"]},
        "last_error" => %{"type" => ["string", "null"]}
      },
      "required" => [
        "id",
        "account_id",
        "document_id",
        "document_title",
        "document_url",
        "agent_version",
        "status",
        "started_at",
        "completed_at",
        "result_summary",
        "last_error"
      ],
      "additionalProperties" => false
    }
  end

  def incident_contact(%IncidentContact{} = contact) do
    %{
      id: contact.id,
      account_id: contact.account_id,
      email: contact.email,
      full_name: contact.full_name,
      role: contact.role,
      source_page: contact.source_page,
      source_excerpt: contact.source_excerpt,
      confidence: decimal_string(contact.confidence),
      document_id: contact.document_id,
      document_title: contact.document && contact.document.title,
      document_url: document_url(contact.document, contact.document_id),
      inserted_at: Tool.iso8601(contact.inserted_at),
      updated_at: Tool.iso8601(contact.updated_at)
    }
  end

  def incident_contact_schema do
    %{
      "type" => "object",
      "properties" => %{
        "id" => %{"type" => "string"},
        "account_id" => %{"type" => ["string", "null"]},
        "email" => %{"type" => "string"},
        "full_name" => %{"type" => ["string", "null"]},
        "role" => %{"type" => ["string", "null"]},
        "source_page" => %{"type" => ["integer", "null"]},
        "source_excerpt" => %{"type" => ["string", "null"]},
        "confidence" => %{"type" => ["string", "null"]},
        "document_id" => %{"type" => ["string", "null"]},
        "document_title" => %{"type" => ["string", "null"]},
        "document_url" => %{"type" => ["string", "null"]},
        "inserted_at" => %{"type" => ["string", "null"]},
        "updated_at" => %{"type" => ["string", "null"]}
      },
      "required" => [
        "id",
        "account_id",
        "email",
        "full_name",
        "role",
        "source_page",
        "source_excerpt",
        "confidence",
        "document_id",
        "document_title",
        "document_url",
        "inserted_at",
        "updated_at"
      ],
      "additionalProperties" => false
    }
  end

  def term(term) do
    %{
      id: term.id,
      account_id: Map.get(term, :account_id),
      source: term.source,
      external_id: term.external_id,
      payment: term.payment,
      start_date: Tool.iso8601(term.start_date),
      end_date: Tool.iso8601(term.end_date),
      seats: term.seats,
      price_per_seat: decimal_string(term.price_per_seat),
      discount: decimal_string(term.discount),
      total: decimal_string(term.total),
      currency: term.currency,
      on_premise: term.on_premise,
      renewal_notice_weeks: term.renewal_notice_weeks,
      po_number: term.po_number,
      inserted_at: Tool.iso8601(Map.get(term, :inserted_at)),
      updated_at: Tool.iso8601(Map.get(term, :updated_at))
    }
  end

  def term_schema do
    %{
      "type" => "object",
      "properties" => %{
        "id" => %{"type" => "string"},
        "account_id" => %{"type" => ["string", "null"]},
        "source" => %{"type" => ["string", "null"]},
        "external_id" => %{"type" => ["string", "null"]},
        "payment" => %{"type" => ["string", "null"]},
        "start_date" => %{"type" => ["string", "null"]},
        "end_date" => %{"type" => ["string", "null"]},
        "seats" => %{"type" => ["integer", "null"]},
        "price_per_seat" => %{"type" => ["string", "null"]},
        "discount" => %{"type" => ["string", "null"]},
        "total" => %{"type" => ["string", "null"]},
        "currency" => %{"type" => ["string", "null"]},
        "on_premise" => %{"type" => ["boolean", "null"]},
        "renewal_notice_weeks" => %{"type" => ["integer", "null"]},
        "po_number" => %{"type" => ["string", "null"]},
        "inserted_at" => %{"type" => ["string", "null"]},
        "updated_at" => %{"type" => ["string", "null"]}
      },
      "required" => [
        "id",
        "account_id",
        "source",
        "external_id",
        "payment",
        "start_date",
        "end_date",
        "seats",
        "price_per_seat",
        "discount",
        "total",
        "currency",
        "on_premise",
        "renewal_notice_weeks",
        "po_number",
        "inserted_at",
        "updated_at"
      ],
      "additionalProperties" => false
    }
  end

  def invoice(invoice) do
    %{
      id: invoice.id,
      external_id: invoice.external_id,
      source: invoice.source,
      number: invoice.number,
      due_date: Tool.iso8601(invoice.due_date),
      amount_value: invoice.amount_value && Decimal.to_string(invoice.amount_value),
      amount_currency: invoice.amount_currency,
      status: invoice.status,
      stripe_url: invoice.stripe_url,
      inserted_at: Tool.iso8601(invoice.inserted_at),
      updated_at: Tool.iso8601(invoice.updated_at)
    }
  end

  def invoice_schema do
    %{
      "type" => "object",
      "properties" => %{
        "id" => %{"type" => "string"},
        "external_id" => %{"type" => ["string", "null"]},
        "source" => %{"type" => ["string", "null"]},
        "number" => %{"type" => ["string", "null"]},
        "due_date" => %{"type" => ["string", "null"]},
        "amount_value" => %{"type" => ["string", "null"]},
        "amount_currency" => %{"type" => ["string", "null"]},
        "status" => %{"type" => ["string", "null"]},
        "stripe_url" => %{"type" => ["string", "null"]},
        "inserted_at" => %{"type" => ["string", "null"]},
        "updated_at" => %{"type" => ["string", "null"]}
      },
      "required" => [
        "id",
        "external_id",
        "source",
        "number",
        "due_date",
        "amount_value",
        "amount_currency",
        "status",
        "stripe_url",
        "inserted_at",
        "updated_at"
      ],
      "additionalProperties" => false
    }
  end

  defp document_url(%Document{} = document, _document_id), do: Tool.document_url(document)
  defp document_url(_document, document_id) when is_binary(document_id), do: Tool.document_url(document_id)
  defp document_url(_document, _document_id), do: nil

  defp author_email(%{author: %{email: email}}), do: email
  defp author_email(_event), do: nil

  defp related_outcome_title(%{outcome: %{title: title}}), do: title
  defp related_outcome_title(_proposal), do: nil

  defp decimal_string(nil), do: nil

  defp decimal_string(%Decimal{} = decimal) do
    decimal
    |> Decimal.normalize()
    |> Decimal.to_string(:normal)
  end
end
