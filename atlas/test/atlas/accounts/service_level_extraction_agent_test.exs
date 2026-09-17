defmodule Atlas.Accounts.ServiceLevelExtractionAgentTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Atlas.Accounts.Account
  alias Atlas.Accounts.Agents.ServiceLevelExtractionAgent
  alias Atlas.Accounts.ServiceLevel
  alias Atlas.Documents.Document
  alias Atlas.Documents.DocumentPage
  alias Atlas.Documents.DocumentType

  setup :verify_on_exit!

  test "extract/1 builds a service-level prompt and output schema from candidate pages" do
    document = %Document{
      id: "doc-123",
      title: "Acme SLA",
      original_filename: "acme-sla.pdf",
      document_date: ~D[2026-01-01],
      account: %Account{name: "Acme"},
      document_type: %DocumentType{name: "Service Level Agreement"},
      pages: [
        %DocumentPage{page_number: 1, content: "Pricing schedule without commitments."},
        %DocumentPage{page_number: 2, content: "Service Level: monthly uptime will be at least 99.9%."}
      ]
    }

    expect(Atlas.LLMs, :config, fn ->
      %{model: "openai:gpt-4o-mini", api_key: "test-key"}
    end)

    expect(Condukt, :run, fn prompt, opts ->
      assert prompt =~ "Extract service levels and security-incident notification contacts from this account document."
      assert prompt =~ "Acme SLA"
      assert prompt =~ "Page 2:"
      assert prompt =~ "monthly uptime will be at least 99.9%"
      refute prompt =~ "Pricing schedule without commitments"

      assert Keyword.fetch!(opts, :api_key) == "test-key"
      assert Keyword.fetch!(opts, :load_project_instructions) == false
      assert Keyword.fetch!(opts, :max_turns) == 1
      assert Keyword.fetch!(opts, :system_prompt) =~ "Return an empty service_levels list"
      assert Keyword.fetch!(opts, :system_prompt) =~ "Return an empty incident_contacts list"
      assert Keyword.fetch!(opts, :system_prompt) =~ "Omit optional fields"
      assert Keyword.fetch!(opts, :system_prompt) =~ "Never use placeholder strings"

      assert %{
               required: ["service_levels", "incident_contacts"],
               properties: %{
                 service_levels: %{
                   type: "array",
                   items: %{
                     required: ["name", "category", "target"],
                     properties: properties
                   }
                 },
                 incident_contacts: %{
                   type: "array",
                   items: %{required: ["email"]}
                 }
               }
             } = Keyword.fetch!(opts, :output)

      assert properties.category.enum == ServiceLevel.categories()

      {:ok, %{"service_levels" => []}}
    end)

    assert {:ok, %{"service_levels" => []}} = ServiceLevelExtractionAgent.extract(document)
  end

  test "extract/1 returns a configuration error when no LLM is configured" do
    expect(Atlas.LLMs, :config, fn -> nil end)

    assert {:error, :llm_not_configured} = ServiceLevelExtractionAgent.extract(%Document{})
  end
end
