defmodule Atlas.Accounts.Agents.ServiceLevelExtractionAgent do
  @moduledoc """
  Extracts contractually binding service levels from account documents.
  """

  alias Atlas.Agents.StyleGuide
  alias Atlas.Documents.Document
  alias Atlas.LLMs.Runner

  @candidate_page_limit 20
  @fallback_page_limit 12
  @page_character_limit 3_000
  @keywords ~w(
    availability uptime service\ level sla support response resolution severity incident
    maintenance credit credits backup retention recovery rto rpo security breach notification
  )

  def extract(%Document{} = document) do
    with {:ok, llm} <- Runner.fetch_config() do
      Condukt.run(
        build_prompt(document),
        Runner.client_opts(llm) ++
          [
            system_prompt: system_prompt(),
            load_project_instructions: false,
            max_turns: 1,
            output: output_schema()
          ]
      )
    end
  end

  defp system_prompt do
    """
    You extract service levels and security-incident notification contacts from
    signed customer terms, master service agreements, order forms, service level agreements, and
    support exhibits.

    Return only contractually binding service commitments present in the
    supplied document text. Useful service levels include availability or uptime targets,
    support response times, resolution targets, support hours, maintenance
    windows, backup or recovery commitments, data retention commitments,
    service credits, and explicit exclusions.

    Steering:
    - Do not infer commitments from generic marketing text.
    - Do not create a service level unless the document states a measurable or
      operationally actionable commitment.
    - Include the exact page number and a short source excerpt for every
      service level when available.
    - Omit optional fields that are not stated in the document.
    - Never use placeholder strings such as "nil", "null", "none", "N/A", or
      "not specified".
    - Return an empty service_levels list when the document has no service levels.

    A security-incident notification contact is an email address that the
    agreement explicitly designates for notification or escalation of a
    security incident, personal-data breach, or service incident. Return only
    customer-side contacts to which Tuist must send a notification. Do not
    return Tuist contacts or infer recipients from a signatory, billing,
    procurement, legal, or generic account email.
    - Include the exact page number and a short source excerpt for every contact.
    - Return an empty incident_contacts list when the document has no explicit
      incident-notification contact.

    #{StyleGuide.prose_rules()}
    """
  end

  defp build_prompt(%Document{} = document) do
    """
    Extract service levels and security-incident notification contacts from this account document.

    Document:
    - ID: #{document.id}
    - Title: #{document.title}
    - Filename: #{document.original_filename}
    - Type: #{document.document_type && document.document_type.name}
    - Date: #{format_value(document.document_date)}
    - Account: #{document.account && document.account.name}

    Text:
    #{pages_context(document.pages || [])}
    """
  end

  defp pages_context([]), do: "No extracted text is available."

  defp pages_context(pages) do
    pages
    |> candidate_pages()
    |> Enum.map_join("\n\n", fn page ->
      "Page #{page.page_number}:\n#{String.slice(page.content, 0, @page_character_limit)}"
    end)
  end

  defp candidate_pages(pages) do
    matching =
      pages
      |> Enum.filter(&candidate_page?/1)
      |> Enum.take(@candidate_page_limit)

    case matching do
      [] -> Enum.take(pages, @fallback_page_limit)
      _matches -> matching
    end
  end

  defp candidate_page?(page) do
    content = String.downcase(page.content || "")
    Enum.any?(@keywords, &String.contains?(content, String.replace(&1, "\\ ", " ")))
  end

  defp output_schema do
    %{
      type: "object",
      properties: %{
        summary: %{type: "string", description: "Short factual summary of the extracted service levels, if any."},
        service_levels: %{
          type: "array",
          items: %{
            type: "object",
            properties: %{
              name: %{type: "string"},
              category: %{
                type: "string",
                enum: [
                  "availability",
                  "response_time",
                  "resolution_time",
                  "support_hours",
                  "maintenance",
                  "backup",
                  "data_retention",
                  "security",
                  "other"
                ]
              },
              target: %{type: "string", description: "Human-readable target as stated or summarized."},
              target_value: %{
                type: "string",
                description: "Numeric target value when a single number is stated, for example 99.9 or 60."
              },
              target_unit: %{
                type: "string",
                description: "Unit for target_value, for example percent, minutes, hours, days."
              },
              measurement_window: %{type: "string"},
              applies_from: %{type: "string", description: "YYYY-MM-DD when explicitly stated."},
              applies_until: %{type: "string", description: "YYYY-MM-DD when explicitly stated."},
              service_credit: %{type: "string"},
              exclusions: %{type: "string"},
              source_page: %{type: "integer"},
              source_excerpt: %{type: "string"},
              confidence: %{
                type: "string",
                description: "Confidence from 0 to 1 that this is a binding service level."
              },
              metadata: %{type: "object"}
            },
            required: ["name", "category", "target"]
          }
        },
        incident_contacts: %{
          type: "array",
          items: %{
            type: "object",
            properties: %{
              email: %{type: "string"},
              full_name: %{type: "string"},
              role: %{type: "string"},
              source_page: %{type: "integer"},
              source_excerpt: %{type: "string"},
              confidence: %{
                type: "string",
                description:
                  "Confidence from 0 to 1 that the contract explicitly designates this address for incident notification."
              },
              metadata: %{type: "object"}
            },
            required: ["email"]
          }
        },
        metadata: %{type: "object"}
      },
      required: ["service_levels", "incident_contacts"]
    }
  end

  defp format_value(nil), do: "-"
  defp format_value(%Date{} = date), do: Date.to_iso8601(date)
  defp format_value(value), do: to_string(value)
end
