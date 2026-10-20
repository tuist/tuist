defmodule Atlas.Documents.PaperlessTest do
  use Atlas.DataCase, async: true
  use Mimic

  alias Atlas.Documents
  alias Atlas.Documents.Document
  alias Atlas.Documents.Paperless

  @config [base_url: "https://papers.example", token: "secret", enqueue?: false]

  defp stub_paperless(results) do
    stub(Req, :request, fn %Req.Request{} = request ->
      url = to_string(request.url)

      cond do
        String.contains?(url, "/download/") ->
          {:ok,
           %Req.Response{
             status: 200,
             headers: %{"content-type" => ["application/pdf"]},
             body: "%PDF-1.4 fake bytes"
           }}

        String.contains?(url, "/api/documents/") ->
          {:ok, %Req.Response{status: 200, body: %{"results" => results, "next" => nil}}}

        true ->
          {:ok, %Req.Response{status: 404, body: %{}}}
      end
    end)
  end

  test "imports a document, tagging the source and recording the paperless id" do
    stub_paperless([
      %{"id" => 280, "title" => "MSA", "original_file_name" => "msa.pdf", "created" => "2026-05-27"}
    ])

    assert {:ok, %{imported: 1, skipped: 0, failed: 0}} = Paperless.import(@config)

    assert [document] = Repo.all(Document)
    assert document.source == "paperless"
    assert document.original_filename == "msa.pdf"
    assert document.content_type == "application/pdf"
    assert document.attributes["paperless_id"] == 280
    assert document.attributes["paperless_title"] == "MSA"
    assert Documents.imported_from_paperless?(280)
  end

  test "skips documents already imported on a re-run" do
    stub_paperless([
      %{"id" => 280, "title" => "MSA", "original_file_name" => "msa.pdf", "created" => "2026-05-27"}
    ])

    assert {:ok, %{imported: 1}} = Paperless.import(@config)
    assert {:ok, %{imported: 0, skipped: 1, failed: 0}} = Paperless.import(@config)
    assert length(Repo.all(Document)) == 1
  end

  test "respects the limit option" do
    stub_paperless([
      %{"id" => 1, "title" => "A", "original_file_name" => "a.pdf", "created" => "2026-01-01"},
      %{"id" => 2, "title" => "B", "original_file_name" => "b.pdf", "created" => "2026-01-02"}
    ])

    assert {:ok, %{imported: 1}} = Paperless.import(Keyword.put(@config, :limit, 1))
    assert length(Repo.all(Document)) == 1
  end

  test "returns an error when not configured" do
    assert {:error, :paperless_not_configured} = Paperless.import([])
  end

  test "propagates a non-200 listing response instead of importing partially" do
    stub(Req, :request, fn %Req.Request{} = request ->
      if String.contains?(to_string(request.url), "/api/documents/") do
        {:ok, %Req.Response{status: 500, body: %{"detail" => "boom"}}}
      else
        {:ok, %Req.Response{status: 200, headers: %{}, body: ""}}
      end
    end)

    assert {:error, {:paperless_list_failed, 500, _}} = Paperless.import(@config)
    assert Repo.all(Document) == []
  end

  test "stops paginating and surfaces an error when a later page fails" do
    stub(Req, :request, fn %Req.Request{} = request ->
      page = request.options[:params][:page]

      cond do
        page == 2 ->
          {:ok, %Req.Response{status: 502, body: %{}}}

        page == 1 ->
          {:ok,
           %Req.Response{
             status: 200,
             body: %{"results" => [%{"id" => 1, "original_file_name" => "a.pdf"}], "next" => "next-page"}
           }}

        true ->
          {:ok, %Req.Response{status: 200, headers: %{}, body: "%PDF"}}
      end
    end)

    assert {:error, {:paperless_list_failed, 502, _}} = Paperless.import(@config)
  end

  test "counts a document as failed when its download errors" do
    stub(Req, :request, fn %Req.Request{} = request ->
      url = to_string(request.url)

      cond do
        String.contains?(url, "/download/") ->
          {:ok, %Req.Response{status: 404, body: %{}}}

        String.contains?(url, "/api/documents/") ->
          {:ok,
           %Req.Response{
             status: 200,
             body: %{"results" => [%{"id" => 1, "original_file_name" => "a.pdf"}], "next" => nil}
           }}

        true ->
          {:ok, %Req.Response{status: 200, headers: %{}, body: ""}}
      end
    end)

    assert {:ok, %{imported: 0, skipped: 0, failed: 1}} = Paperless.import(@config)
    assert Repo.all(Document) == []
  end

  test "propagates a transport error from Req" do
    stub(Req, :request, fn %Req.Request{} -> {:error, %Req.TransportError{reason: :timeout}} end)

    assert {:error, %Req.TransportError{reason: :timeout}} = Paperless.import(@config)
  end
end
