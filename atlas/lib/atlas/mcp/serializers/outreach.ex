defmodule Atlas.MCP.Serializers.Outreach do
  @moduledoc false

  alias Atlas.MCP.Tool

  def contact(contact) do
    %{
      id: contact.id,
      account_id: contact.account_id,
      account_name: account_name(contact),
      full_name: contact.full_name,
      email: contact.email,
      title: contact.title,
      linkedin_url: contact.linkedin_url,
      source: contact.source,
      outreach_status: contact.outreach_status,
      outreach_enrolled_at: Tool.iso8601(contact.outreach_enrolled_at),
      last_outreach_at: Tool.iso8601(contact.last_outreach_at)
    }
  end

  def full_contact(contact) do
    contact
    |> contact()
    |> Map.put(:notes, contact.notes)
    |> Map.put(:events, Enum.map(loaded_events(contact), &event/1))
    |> Map.put(
      :next_step,
      contact |> loaded_recommendations() |> Enum.find(&(&1.status == "pending")) |> recommendation()
    )
  end

  def recommendation(nil), do: nil

  def recommendation(recommendation) do
    %{
      id: recommendation.id,
      contact_id: recommendation.contact_id,
      account_id: recommendation.account_id,
      status: recommendation.status,
      action_type: recommendation.action_type,
      recommended_event_kind: recommendation.recommended_event_kind,
      title: recommendation.title,
      guidance: recommendation.guidance,
      rationale: recommendation.rationale,
      draft_subject: if(recommendation.action_type == "inmail", do: recommendation.draft_subject),
      draft_message: recommendation.draft_message,
      due_at: Tool.iso8601(recommendation.due_at),
      confidence: decimal_string(recommendation.confidence),
      evidence: recommendation.evidence,
      generated_by_agent: recommendation.generated_by_agent,
      reviewed_at: Tool.iso8601(recommendation.reviewed_at),
      review_reason: recommendation.review_reason
    }
  end

  def event(event) do
    %{
      id: event.id,
      contact_id: event.contact_id,
      source: event.source,
      kind: event.kind,
      title: event.title,
      subject: event.metadata["subject"],
      body: event.body,
      response_outcome: event.metadata["response_outcome"],
      occurred_at: Tool.iso8601(event.occurred_at),
      author_email: author_email(event)
    }
  end

  def candidate(candidate) do
    %{
      id: candidate.id,
      source: candidate.source,
      source_id: candidate.source_id,
      status: candidate.status,
      full_name: candidate.full_name,
      title: candidate.title,
      organization_name: candidate.organization_name,
      organization_domain: candidate.organization_domain,
      linkedin_url: candidate.linkedin_url,
      email: candidate.email,
      search_segment: candidate.search_segment,
      search_version: candidate.search_version,
      search_rank: candidate.search_rank,
      rejection_reason: candidate.rejection_reason,
      contact_id: candidate.contact_id,
      discovered_at: Tool.iso8601(candidate.discovered_at),
      reviewed_at: Tool.iso8601(candidate.reviewed_at)
    }
  end

  def contact_schema do
    nullable_string = %{"type" => ["string", "null"]}

    %{
      "type" => "object",
      "properties" => %{
        "id" => %{"type" => "string"},
        "account_id" => %{"type" => "string"},
        "account_name" => nullable_string,
        "full_name" => %{"type" => "string"},
        "email" => nullable_string,
        "title" => nullable_string,
        "linkedin_url" => nullable_string,
        "source" => %{"type" => "string"},
        "outreach_status" => %{"type" => "string"},
        "outreach_enrolled_at" => nullable_string,
        "last_outreach_at" => nullable_string
      },
      "required" =>
        ~w(id account_id account_name full_name email title linkedin_url source outreach_status outreach_enrolled_at last_outreach_at),
      "additionalProperties" => false
    }
  end

  def full_contact_schema do
    base = contact_schema()

    %{
      base
      | "properties" =>
          base["properties"]
          |> Map.put("notes", %{"type" => ["string", "null"]})
          |> Map.put("events", %{"type" => "array", "items" => event_schema()})
          |> Map.put("next_step", %{"anyOf" => [recommendation_schema(), %{"type" => "null"}]}),
        "required" => base["required"] ++ ["notes", "events", "next_step"]
    }
  end

  def recommendation_schema do
    nullable_string = %{"type" => ["string", "null"]}

    %{
      "type" => "object",
      "properties" => %{
        "id" => %{"type" => "string"},
        "contact_id" => %{"type" => "string"},
        "account_id" => %{"type" => "string"},
        "status" => %{"type" => "string"},
        "action_type" => %{"type" => "string"},
        "recommended_event_kind" => nullable_string,
        "title" => %{"type" => "string"},
        "guidance" => %{"type" => "string"},
        "rationale" => %{"type" => "string"},
        "draft_subject" => nullable_string,
        "draft_message" => nullable_string,
        "due_at" => %{"type" => "string"},
        "confidence" => %{"type" => "string"},
        "evidence" => %{"type" => "object"},
        "generated_by_agent" => %{"type" => "string"},
        "reviewed_at" => nullable_string,
        "review_reason" => nullable_string
      },
      "required" =>
        ~w(id contact_id account_id status action_type recommended_event_kind title guidance rationale draft_subject draft_message due_at confidence evidence generated_by_agent reviewed_at review_reason),
      "additionalProperties" => false
    }
  end

  def recommendation_response(recommendation) do
    %{recommendation: recommendation(recommendation)}
  end

  def recommendation_response_schema do
    %{
      "type" => "object",
      "properties" => %{
        "recommendation" => %{"anyOf" => [recommendation_schema(), %{"type" => "null"}]}
      },
      "required" => ["recommendation"],
      "additionalProperties" => false
    }
  end

  def event_schema do
    nullable_string = %{"type" => ["string", "null"]}

    %{
      "type" => "object",
      "properties" => %{
        "id" => %{"type" => "string"},
        "contact_id" => %{"type" => "string"},
        "source" => %{"type" => "string"},
        "kind" => %{"type" => "string"},
        "title" => %{"type" => "string"},
        "subject" => nullable_string,
        "body" => nullable_string,
        "response_outcome" => nullable_string,
        "occurred_at" => %{"type" => "string"},
        "author_email" => nullable_string
      },
      "required" => ~w(id contact_id source kind title subject body response_outcome occurred_at author_email),
      "additionalProperties" => false
    }
  end

  def candidate_schema do
    nullable_string = %{"type" => ["string", "null"]}
    nullable_integer = %{"type" => ["integer", "null"]}

    %{
      "type" => "object",
      "properties" => %{
        "id" => %{"type" => "string"},
        "source" => %{"type" => "string"},
        "source_id" => %{"type" => "string"},
        "status" => %{"type" => "string"},
        "full_name" => nullable_string,
        "title" => nullable_string,
        "organization_name" => nullable_string,
        "organization_domain" => nullable_string,
        "linkedin_url" => nullable_string,
        "email" => nullable_string,
        "search_segment" => %{"type" => "string"},
        "search_version" => %{"type" => "integer"},
        "search_rank" => nullable_integer,
        "rejection_reason" => nullable_string,
        "contact_id" => nullable_string,
        "discovered_at" => %{"type" => "string"},
        "reviewed_at" => nullable_string
      },
      "required" =>
        ~w(id source source_id status full_name title organization_name organization_domain linkedin_url email search_segment search_version search_rank rejection_reason contact_id discovered_at reviewed_at),
      "additionalProperties" => false
    }
  end

  def list_response(contacts) do
    %{contacts: Enum.map(contacts, &contact/1), count: length(contacts)}
  end

  def list_response_schema do
    %{
      "type" => "object",
      "properties" => %{
        "contacts" => %{"type" => "array", "items" => contact_schema()},
        "count" => %{"type" => "integer"}
      },
      "required" => ["contacts", "count"],
      "additionalProperties" => false
    }
  end

  def candidate_list_response(candidates) do
    %{candidates: Enum.map(candidates, &candidate/1), count: length(candidates)}
  end

  def candidate_list_response_schema do
    %{
      "type" => "object",
      "properties" => %{
        "candidates" => %{"type" => "array", "items" => candidate_schema()},
        "count" => %{"type" => "integer"}
      },
      "required" => ["candidates", "count"],
      "additionalProperties" => false
    }
  end

  defp account_name(%{account: %Ecto.Association.NotLoaded{}}), do: nil
  defp account_name(%{account: nil}), do: nil
  defp account_name(%{account: account}), do: account.name

  defp loaded_events(%{events: %Ecto.Association.NotLoaded{}}), do: []
  defp loaded_events(%{events: events}) when is_list(events), do: events
  defp loaded_events(_contact), do: []

  defp loaded_recommendations(%{outreach_recommendations: %Ecto.Association.NotLoaded{}}), do: []

  defp loaded_recommendations(%{outreach_recommendations: recommendations}) when is_list(recommendations),
    do: recommendations

  defp loaded_recommendations(_contact), do: []

  defp author_email(%{author: %Ecto.Association.NotLoaded{}}), do: nil
  defp author_email(%{author: nil}), do: nil
  defp author_email(%{author: author}), do: author.email

  defp decimal_string(%Decimal{} = value), do: Decimal.to_string(value, :normal)
  defp decimal_string(value), do: to_string(value)
end
