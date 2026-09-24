defmodule Atlas.MCP.Tools.GetContractTemplateTest do
  use Atlas.MCP.ToolCase

  alias Atlas.Contracts
  alias Atlas.MCP.Server
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

  test "tools/call returns the download URL as text content only, with no null _meta" do
    conn = executive_mcp_conn()

    response =
      Server.handle_message(conn, %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "tools/call",
        "params" => %{
          "name" => "get_contract_template",
          "arguments" => %{"template_set" => "2026-02", "filename" => "msa.docx"}
        }
      })

    %{"result" => result} = response |> JSON.encode!() |> JSON.decode!()

    refute null_meta?(result)
    refute result["isError"]
    assert [%{"type" => "text", "text" => text}] = result["content"]
    assert %{"download_url" => download_url} = JSON.decode!(text)
    assert download_url =~ "/contracts/templates/2026-02/msa.docx?token="
    assert result["structuredContent"]["download_url"] == download_url
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

  defp null_meta?(value) when is_map(value) do
    Enum.any?(value, fn
      {"_meta", nil} -> true
      {_key, nested} -> null_meta?(nested)
    end)
  end

  defp null_meta?(value) when is_list(value), do: Enum.any?(value, &null_meta?/1)
  defp null_meta?(_value), do: false
end
