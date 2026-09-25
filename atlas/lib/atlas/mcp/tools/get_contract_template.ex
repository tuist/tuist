defmodule Atlas.MCP.Tools.GetContractTemplate do
  @moduledoc """
  Returns a signed, short-lived download URL plus metadata for one contract
  Word template. The template is not embedded in the result: MCP relays between
  Atlas and the client rewrite embedded binary resources into items the client
  rejects, which discards the whole result along with the URL.
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
      "Get a signed download URL for an official Atlas order form, Master Services Agreement, annex, or enterprise-contract Word template. Use after generate_enterprise_contract or list_contract_templates, then download the file from download_url before expires_at."

  def execute(conn, args) do
    with :ok <- Tool.authorize_scope(conn, "contracts:read", "Contract templates"),
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
end
