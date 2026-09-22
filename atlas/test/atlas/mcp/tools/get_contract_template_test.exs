defmodule Atlas.MCP.Tools.GetContractTemplateTest do
  use Atlas.MCP.ToolCase

  alias Atlas.Contracts
  alias Atlas.MCP.Tools.GetContractTemplate

  test "returns a signed URL that verifies back to the same template" do
    conn = executive_mcp_conn()

    {:ok, payload} =
      execute_tool(GetContractTemplate, conn, %{
        "template_set" => "2026-02",
        "filename" => "msa.docx"
      })

    assert payload.template_set == "2026-02"
    assert payload.filename == "msa.docx"
    assert payload.kind == :msa
    assert payload.content_type =~ "wordprocessingml"
    assert payload.byte_size > 0
    assert payload.download_url =~ "/contracts/templates/2026-02/msa.docx?token="
    assert {:ok, _datetime, _offset} = DateTime.from_iso8601(payload.expires_at)

    %URI{query: query} = URI.parse(payload.download_url)
    token = query |> URI.decode_query() |> Map.fetch!("token")

    assert {:ok, %{"template_set" => "2026-02", "filename" => "msa.docx"}} =
             Contracts.verify_download_token(token)
  end

  test "defaults to the current template set when none is provided" do
    conn = executive_mcp_conn()

    {:ok, payload} = execute_tool(GetContractTemplate, conn, %{"filename" => "msa.docx"})

    assert payload.template_set == Contracts.default_template_set()
  end

  test "attaches the Word template as an embedded binary resource" do
    conn = executive_mcp_conn()

    response =
      GetContractTemplate.call(conn, %{
        "template_set" => "2026-02",
        "filename" => "msa.docx"
      })

    assert %{
             "content" => [
               %{"type" => "text"},
               %{
                 "type" => "resource",
                 "resource" => %{
                   "uri" => uri,
                   "mimeType" => content_type,
                   "blob" => encoded_contents
                 }
               }
             ],
             "structuredContent" => %{"filename" => "msa.docx"}
           } = response

    assert uri =~ "/contracts/templates/2026-02/msa.docx?token="
    assert content_type == Contracts.docx_content_type()

    {:ok, template} = Contracts.fetch_template("2026-02", "msa.docx")
    assert Base.decode64!(encoded_contents) == File.read!(Contracts.template_path(template))
  end

  test "returns an error when the filename is unknown" do
    conn = executive_mcp_conn()

    assert {:error, "Template not found."} =
             execute_tool(GetContractTemplate, conn, %{"filename" => "not-a-template.docx"})
  end

  test "requires a filename" do
    conn = executive_mcp_conn()

    assert {:error, "filename is required."} = execute_tool(GetContractTemplate, conn, %{})
  end

  test "refuses non-executive users" do
    user = insert_user!(%{role: :employee})

    assert {:error, message} =
             execute_tool(GetContractTemplate, mcp_conn(user), %{"filename" => "msa.docx"})

    assert message =~ "Contract templates"
  end
end
