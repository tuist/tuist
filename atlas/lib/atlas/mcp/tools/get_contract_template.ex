defmodule Atlas.MCP.Tools.GetContractTemplate do
  @moduledoc """
  Attaches one contract Word template as an embedded binary resource and also
  returns a signed download URL plus metadata. Hosted clients can consume the
  resource without browser, terminal, or local-folder access; clients with a
  filesystem can use the URL as a fallback.
  """

  use Atlas.MCP.Tool,
    name: "get_contract_template",
    schema: %{
      "type" => "object",
      "description" => "Returns a signed download URL for a contract template.",
      "required" => ["filename"],
      "properties" => %{
        "template_set" => %{
          "type" => "string",
          "description" => "Template set folder name (e.g. \"2026-02\"). Defaults to the current set."
        },
        "filename" => %{
          "type" => "string",
          "description" => "Template filename, e.g. \"msa.docx\"."
        }
      }
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "template_set" => %{"type" => "string"},
        "filename" => %{"type" => "string"},
        "kind" => %{"type" => "string"},
        "title" => %{"type" => "string"},
        "byte_size" => %{"type" => "integer"},
        "content_type" => %{"type" => "string"},
        "download_url" => %{"type" => "string"},
        "expires_at" => %{"type" => "string"}
      },
      "required" => [
        "template_set",
        "filename",
        "kind",
        "title",
        "byte_size",
        "content_type",
        "download_url",
        "expires_at"
      ],
      "additionalProperties" => false
    }

  alias Atlas.Contracts
  alias Atlas.Contracts.Template
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description,
    do:
      "Attach an official Atlas order form, Master Services Agreement, annex, or enterprise-contract Word template directly to the conversation. Use after generate_enterprise_contract or list_contract_templates; no browser or terminal hand-off is needed."

  @impl EMCP.Tool
  def call(conn, args) do
    case execute(conn, args) do
      {:ok, payload} -> response_with_template_resource(payload)
      error -> Tool.respond(error, __MODULE__)
    end
  end

  def execute(conn, args) do
    with :ok <- Tool.authorize_executive(conn, "Contract templates"),
         {:ok, filename} <- fetch_filename(args),
         template_set = args["template_set"] || Contracts.default_template_set(),
         {:ok, %Template{} = template} <- Contracts.fetch_template(template_set, filename) do
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      expires_at = DateTime.add(now, Contracts.download_max_age(), :second)

      {:ok,
       %{
         template_set: template.template_set,
         filename: template.filename,
         kind: template.kind,
         title: template.title,
         byte_size: template.byte_size,
         content_type: Contracts.docx_content_type(),
         download_url: Contracts.download_url(template),
         expires_at: DateTime.to_iso8601(expires_at)
       }}
    else
      {:error, :not_found} -> {:error, "Template not found."}
      {:error, message} when is_binary(message) -> {:error, message}
    end
  end

  defp fetch_filename(%{"filename" => filename}) when is_binary(filename) and filename != "" do
    {:ok, filename}
  end

  defp fetch_filename(_args), do: {:error, "filename is required."}

  defp response_with_template_resource(payload) do
    with {:ok, template} <- Contracts.fetch_template(payload.template_set, payload.filename),
         {:ok, contents} <- Contracts.read_template(template) do
      response = Tool.json_response(payload, __MODULE__)

      resource = %{
        "type" => "resource",
        "resource" => %{
          "uri" => payload.download_url,
          "mimeType" => payload.content_type,
          "blob" => Base.encode64(contents)
        }
      }

      Map.update!(response, "content", &(&1 ++ [resource]))
    else
      {:error, reason} -> Tool.respond({:error, "Could not attach contract template: #{inspect(reason)}"}, __MODULE__)
    end
  end
end
