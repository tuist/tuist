defmodule Atlas.MCP.Tools.GetDocument do
  @moduledoc false

  use Atlas.MCP.Tool,
    name: "get_document",
    schema: %{
      "type" => "object",
      "required" => ["document_id"],
      "properties" => %{
        "document_id" => %{"type" => "string", "description" => "Atlas document id."},
        "start_page" => %{
          "type" => "integer",
          "minimum" => 1,
          "description" => "First extracted page number to return. Defaults to 1."
        },
        "page_size" => %{
          "type" => "integer",
          "minimum" => 1,
          "maximum" => 25,
          "description" => "Number of extracted pages to return. Defaults to 10."
        }
      }
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "id" => %{"type" => "string"},
        "title" => %{"type" => ["string", "null"]},
        "original_filename" => %{"type" => ["string", "null"]},
        "content_type" => %{"type" => ["string", "null"]},
        "status" => %{"type" => "string"},
        "document_type" => %{"type" => ["string", "null"]},
        "correspondent" => %{"type" => ["string", "null"]},
        "account" =>
          Atlas.MCP.Tool.nullable(%{
            "type" => "object",
            "properties" => %{
              "id" => %{"type" => "string"},
              "account_key" => %{"type" => "string"},
              "name" => %{"type" => ["string", "null"]},
              "primary_domain" => %{"type" => ["string", "null"]},
              "url" => %{"type" => "string"}
            },
            "required" => ["id", "account_key", "name", "primary_domain", "url"],
            "additionalProperties" => false
          }),
        "tags" => %{"type" => "array", "items" => %{"type" => "string"}},
        "document_date" => %{"type" => ["string", "null"]},
        "archive_serial_number" => %{"type" => ["integer", "null"]},
        "summary" => %{"type" => ["string", "null"]},
        "attributes" => %{"type" => "object"},
        "url" => %{"type" => "string"},
        "pages" => %{
          "type" => "array",
          "items" => %{
            "type" => "object",
            "properties" => %{
              "page_number" => %{"type" => "integer"},
              "content" => %{"type" => "string"},
              "metadata" => %{"type" => "object"}
            },
            "required" => ["page_number", "content", "metadata"],
            "additionalProperties" => false
          }
        },
        "page_count" => %{"type" => "integer"},
        "start_page" => %{"type" => "integer"},
        "page_size" => %{"type" => "integer"},
        "pages_returned" => %{"type" => "integer"},
        "next_start_page" => %{"type" => ["integer", "null"]},
        "inserted_at" => %{"type" => ["string", "null"]},
        "processed_at" => %{"type" => ["string", "null"]}
      },
      "required" => [
        "id",
        "title",
        "original_filename",
        "content_type",
        "status",
        "document_type",
        "correspondent",
        "account",
        "tags",
        "document_date",
        "archive_serial_number",
        "summary",
        "attributes",
        "url",
        "pages",
        "page_count",
        "start_page",
        "page_size",
        "pages_returned",
        "next_start_page",
        "inserted_at",
        "processed_at"
      ],
      "additionalProperties" => false
    }

  alias Atlas.Documents
  alias Atlas.Documents.Document
  alias Atlas.MCP.Tool

  @default_page_size 10
  @max_page_size 25

  @impl EMCP.Tool
  def description,
    do:
      "Get a document with paginated extracted page text, normalized metadata (document type, correspondent, tags, date, archive serial number), and a shareable url to open the file."

  def execute(conn, %{"document_id" => document_id} = args) do
    start_page = input_start_page(args)
    page_size = page_size(args)

    with :ok <- Tool.authorize_scope(conn, "documents:read", "Document tools"),
         %Document{} = document <-
           Documents.get_document(document_id, pages: false) do
      {pages, page_meta} =
        Documents.list_document_pages_page(document,
          limit: page_size,
          offset: start_page - 1
        )

      {:ok, serialize_document(document, pages, page_meta)}
    else
      nil -> {:error, "Document not found."}
      {:error, reason} -> {:error, reason}
    end
  end

  def execute(_conn, _args), do: {:error, "document_id is required."}

  defp serialize_document(%Document{} = document, pages, %Flop.Meta{} = page_meta) do
    pages = Enum.map(pages, &serialize_page/1)

    %{
      id: document.id,
      title: document.title,
      original_filename: document.original_filename,
      content_type: document.content_type,
      status: document.status,
      document_type: document.document_type && document.document_type.name,
      correspondent: document.correspondent && document.correspondent.name,
      account: serialize_account(document.account),
      tags: Enum.map(document.tags, & &1.name),
      document_date: Tool.iso8601(document.document_date),
      archive_serial_number: document.archive_serial_number,
      summary: document.summary,
      attributes: document.attributes,
      url: Tool.document_url(document),
      pages: pages,
      page_count: page_meta.total_count,
      start_page: start_page(page_meta),
      page_size: page_meta.page_size,
      pages_returned: length(pages),
      next_start_page: next_start_page(page_meta),
      inserted_at: Tool.iso8601(document.inserted_at),
      processed_at: Tool.iso8601(document.processed_at)
    }
  end

  defp serialize_page(page) do
    %{page_number: page.page_number, content: page.content, metadata: page.metadata}
  end

  defp start_page(%Flop.Meta{current_offset: offset}) when is_integer(offset), do: offset + 1
  defp start_page(%Flop.Meta{}), do: 1

  defp next_start_page(%Flop.Meta{has_next_page?: true, next_offset: offset}) when is_integer(offset), do: offset + 1
  defp next_start_page(%Flop.Meta{}), do: nil

  defp input_start_page(args) do
    case Map.get(args, "start_page") do
      value when is_integer(value) and value > 0 -> value
      _ -> 1
    end
  end

  defp page_size(args) do
    case Map.get(args, "page_size") do
      value when is_integer(value) and value > 0 -> min(value, @max_page_size)
      _ -> @default_page_size
    end
  end

  defp serialize_account(nil), do: nil

  defp serialize_account(account) do
    %{
      id: account.id,
      account_key: account.account_key,
      name: account.name,
      primary_domain: account.primary_domain,
      url: Tool.account_url(account.id)
    }
  end
end
