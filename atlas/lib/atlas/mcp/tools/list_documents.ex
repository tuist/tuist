defmodule Atlas.MCP.Tools.ListDocuments do
  @moduledoc false

  use Atlas.MCP.Tool,
    name: "list_documents",
    schema: %{
      "type" => "object",
      "properties" =>
        %{
          "query" => %{"type" => "string", "description" => "Search title, filename, or summary."},
          "document_type" => %{
            "type" => "string",
            "description" => "Filter by document type name (e.g. invoice, contract)."
          },
          "correspondent" => %{"type" => "string", "description" => "Filter by correspondent name."},
          "status" => %{"type" => "string", "enum" => Atlas.Documents.Document.statuses()},
          "page_size" => %{"type" => "integer", "minimum" => 1, "maximum" => 100}
        }
        |> Map.merge(Atlas.MCP.AccountLookup.identifier_schema_properties())
    },
    output_schema:
      Atlas.MCP.Serializers.Accounts.list_response_schema(:documents, %{
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
          "inserted_at",
          "processed_at"
        ],
        "additionalProperties" => false
      })

  alias Atlas.Documents
  alias Atlas.Documents.Document
  alias Atlas.MCP.AccountLookup
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description,
    do:
      "List executive documents stored in Atlas, including document type, correspondent, tags, date, and a shareable url to open each file."

  def execute(conn, args) do
    with :ok <- Tool.authorize_executive(conn, "Document tools"),
         {:ok, account_id} <- account_id(args) do
      documents =
        [
          limit: Tool.page_size(args),
          account_id: account_id,
          query: present(args["query"]),
          document_type: present(args["document_type"]),
          correspondent: present(args["correspondent"]),
          status: present(args["status"])
        ]
        |> Enum.reject(fn {_key, value} -> is_nil(value) end)
        |> Documents.list_documents()
        |> Enum.map(&serialize_document/1)

      {:ok, %{documents: documents, count: length(documents)}}
    end
  end

  defp serialize_document(%Document{} = document) do
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
      inserted_at: Tool.iso8601(document.inserted_at),
      processed_at: Tool.iso8601(document.processed_at)
    }
  end

  defp present(value) when is_binary(value) do
    value = String.trim(value)
    if value != "", do: value
  end

  defp present(_value), do: nil

  defp account_id(args) do
    if Enum.any?(["account_id", "account_key", "handle"], &present(args[&1])) do
      case AccountLookup.resolve(args) do
        {:ok, account} -> {:ok, account.id}
        {:error, reason} -> {:error, reason}
      end
    else
      {:ok, nil}
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
