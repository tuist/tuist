defmodule Atlas.MCP.Tools.ListContractTemplates do
  @moduledoc """
  Lists the `.docx` contract templates Atlas ships for a given template set
  (default: the current set). Use `get_contract_template` to retrieve a
  short-lived signed download URL for any of the listed entries.
  """

  use Atlas.MCP.Tool,
    name: "list_contract_templates",
    schema: %{
      "type" => "object",
      "description" => "Lists contract templates shipped with Atlas.",
      "properties" => %{
        "template_set" => %{
          "type" => "string",
          "description" => "Template set folder name (e.g. \"2026-02\"). Defaults to the current set."
        }
      }
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "template_set" => %{"type" => "string"},
        "available_template_sets" => %{"type" => "array", "items" => %{"type" => "string"}},
        "templates" => %{
          "type" => "array",
          "items" => %{
            "type" => "object",
            "properties" => %{
              "filename" => %{"type" => "string"},
              "kind" => %{"type" => "string"},
              "title" => %{"type" => "string"},
              "byte_size" => %{"type" => "integer"}
            },
            "required" => ["filename", "kind", "title", "byte_size"],
            "additionalProperties" => false
          }
        }
      },
      "required" => ["template_set", "available_template_sets", "templates"],
      "additionalProperties" => false
    }

  alias Atlas.Contracts
  alias Atlas.Contracts.Template
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description,
    do:
      "List the official Word templates Atlas ships for order forms, Master Services Agreements, and enterprise contracts. Use after generate_enterprise_contract to confirm the files required by its workflow; never draft a substitute from scratch."

  def execute(conn, args) do
    with :ok <- Tool.authorize_executive(conn, "Contract templates") do
      template_set = args["template_set"] || Contracts.default_template_set()

      {:ok,
       %{
         template_set: template_set,
         available_template_sets: Contracts.list_template_sets(),
         templates: template_set |> Contracts.list_templates() |> Enum.map(&serialize/1)
       }}
    end
  end

  defp serialize(%Template{} = template) do
    %{
      filename: template.filename,
      kind: template.kind,
      title: template.title,
      byte_size: template.byte_size
    }
  end
end
