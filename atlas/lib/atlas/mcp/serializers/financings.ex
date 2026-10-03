defmodule Atlas.MCP.Serializers.Financings do
  @moduledoc false

  alias Atlas.Finance.Financing
  alias Atlas.MCP.Tool

  def financing_schema do
    %{
      "type" => "object",
      "properties" => %{
        "id" => %{"type" => "string"},
        "type" => %{"type" => "string"},
        "accounting_treatment" => %{"type" => "string"},
        "status" => %{"type" => "string"},
        "provider" => %{"type" => "string"},
        "supplier" => %{"type" => ["string", "null"]},
        "reference" => %{"type" => ["string", "null"]},
        "disbursement_or_commencement_on" => %{"type" => "string", "format" => "date"},
        "term_months" => %{"type" => ["integer", "null"]},
        "currency" => %{"type" => "string"},
        "undiscounted_commitment" => %{"type" => "string"},
        "initial_liability" => %{"type" => ["string", "null"]},
        "principal_amount" => %{"type" => ["string", "null"]},
        "purchase_option_amount" => %{"type" => ["string", "null"]},
        "purchase_option_available_from" => %{"type" => ["string", "null"], "format" => "date"},
        "asset_allocations" => %{"type" => "array", "items" => asset_allocation_schema()},
        "documents" => %{"type" => "array", "items" => financing_document_schema()},
        "financings_url" => %{"type" => "string"}
      },
      "required" => [
        "id",
        "type",
        "accounting_treatment",
        "status",
        "provider",
        "asset_allocations",
        "documents",
        "disbursement_or_commencement_on",
        "currency",
        "undiscounted_commitment",
        "financings_url"
      ],
      "additionalProperties" => false
    }
  end

  def financing(%Financing{} = f) do
    %{
      id: f.id,
      type: f.type,
      accounting_treatment: f.accounting_treatment,
      status: f.status,
      provider: f.provider,
      supplier: f.supplier,
      reference: f.reference,
      disbursement_or_commencement_on: Date.to_iso8601(f.disbursement_or_commencement_on),
      term_months: f.term_months,
      currency: f.currency,
      undiscounted_commitment: decimal_string(f.undiscounted_commitment),
      initial_liability: decimal_string(f.initial_liability),
      principal_amount: decimal_string(f.principal_amount),
      purchase_option_amount: decimal_string(f.purchase_option_amount),
      purchase_option_available_from: iso_date(f.purchase_option_available_from),
      asset_allocations: asset_allocations(f.lines),
      documents: financing_documents(f.documents),
      financings_url: Tool.financing_url(f.id)
    }
  end

  def financing_list_schema do
    %{
      "type" => "object",
      "properties" => %{
        "financings" => %{"type" => "array", "items" => financing_schema()},
        "count" => %{"type" => "integer"}
      },
      "required" => ["financings", "count"],
      "additionalProperties" => false
    }
  end

  def financing_list(rows) do
    %{financings: Enum.map(rows, &financing/1), count: length(rows)}
  end

  defp decimal_string(nil), do: nil
  defp decimal_string(%Decimal{} = d), do: Decimal.to_string(d, :normal)

  defp iso_date(nil), do: nil
  defp iso_date(%Date{} = d), do: Date.to_iso8601(d)

  defp financing_document_schema do
    %{
      "type" => "object",
      "properties" => %{
        "id" => %{"type" => "string"},
        "document_id" => %{"type" => "string"},
        "kind" => %{"type" => "string"},
        "title" => %{"type" => ["string", "null"]},
        "notes" => %{"type" => ["string", "null"]},
        "document_url" => %{"type" => "string"}
      },
      "required" => ["id", "document_id", "kind", "document_url"],
      "additionalProperties" => false
    }
  end

  defp asset_allocation_schema do
    %{
      "type" => "object",
      "properties" => %{
        "asset_id" => %{"type" => "string"},
        "share_basis_points" => %{"type" => "integer"},
        "hardware_url" => %{"type" => "string"}
      },
      "required" => ["asset_id", "share_basis_points", "hardware_url"],
      "additionalProperties" => false
    }
  end

  defp asset_allocations(%Ecto.Association.NotLoaded{}), do: []
  defp asset_allocations(nil), do: []

  defp asset_allocations(lines) do
    Enum.map(lines, fn line ->
      %{
        asset_id: line.asset_id,
        share_basis_points: line.share_bps,
        hardware_url: Tool.asset_url(line.asset_id)
      }
    end)
  end

  defp financing_documents(%Ecto.Association.NotLoaded{}), do: []
  defp financing_documents(nil), do: []

  defp financing_documents(links) do
    Enum.map(links, fn link ->
      %{
        id: link.id,
        document_id: link.document_id,
        kind: link.kind,
        title: document_title(link.document),
        notes: link.notes,
        document_url: Tool.document_url(link.document_id)
      }
    end)
  end

  defp document_title(%{title: title}) when is_binary(title) and title != "", do: title
  defp document_title(%{original_filename: name}) when is_binary(name), do: name
  defp document_title(_document), do: nil
end
