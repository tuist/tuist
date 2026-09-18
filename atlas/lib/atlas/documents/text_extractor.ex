defmodule Atlas.Documents.TextExtractor do
  @moduledoc false

  @max_page_chars 12_000
  @xlsx_sample_rows 20

  def extract_pages(path, content_type, filename) do
    cond do
      pdf?(content_type, filename) ->
        extract_pdf(path)

      docx?(content_type, filename) ->
        extract_docx(path)

      xlsx?(content_type, filename) ->
        extract_xlsx(path, filename)

      text?(content_type, filename) ->
        path |> File.read() |> split_text()

      true ->
        {:error, :unsupported_document_type}
    end
  end

  defp extract_pdf(path) do
    case System.find_executable("pdftotext") do
      nil ->
        {:error, :pdftotext_not_found}

      executable ->
        # Briefly removes the temp file when this process exits, so there is no
        # manual cleanup. MuonTrap.cmd propagates kills to pdftotext if the
        # owning process dies mid-extraction.
        with {:ok, output_path} <- Briefly.create(),
             {_output, 0} <- MuonTrap.cmd(executable, ["-layout", path, output_path]),
             {:ok, text} <- File.read(output_path) do
          split_text({:ok, text})
        else
          {output, _exit_status} when is_binary(output) -> {:error, :pdf_text_extraction_failed}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  # pandoc converts DOCX to plain text without pulling in a heavyweight office
  # suite. Once the text is out, splitting matches the PDF path so pages,
  # embeddings, and classification behave identically for both formats.
  defp extract_docx(path) do
    case System.find_executable("pandoc") do
      nil ->
        {:error, :pandoc_not_found}

      executable ->
        case MuonTrap.cmd(executable, ["--from=docx", "--to=plain", "--wrap=none", path]) do
          {text, 0} -> split_text({:ok, text})
          {_output, _exit_status} -> {:error, :docx_text_extraction_failed}
        end
    end
  end

  # Dumping every row of every sheet as text would flood embeddings with
  # low-signal cell data. Extract a compact per-sheet outline (header row plus
  # a sample of rows) that the classifier will summarize like any other
  # document; the summary lives on `document.summary` and search hits it.
  defp extract_xlsx(path, filename) do
    case XlsxReader.open(path, source: :path) do
      {:ok, package} ->
        sheet_names = XlsxReader.sheet_names(package)

        outline =
          [
            "Spreadsheet: #{Path.basename(filename || path)}",
            "Sheets: #{length(sheet_names)} (#{Enum.join(sheet_names, ", ")})",
            ""
          ]
          |> Kernel.++(Enum.flat_map(sheet_names, &render_xlsx_sheet(package, &1)))
          |> Enum.join("\n")

        split_text({:ok, outline})

      {:error, reason} ->
        {:error, {:xlsx_open_failed, reason}}
    end
  end

  defp render_xlsx_sheet(package, sheet_name) do
    case XlsxReader.sheet(package, sheet_name) do
      {:ok, []} ->
        ["## Sheet: #{sheet_name}", "(empty)", ""]

      {:ok, [header | rest]} ->
        sample = Enum.take(rest, @xlsx_sample_rows)

        [
          "## Sheet: #{sheet_name}",
          "Rows (excluding header): #{length(rest)}",
          "Columns: #{Enum.map_join(header, " | ", &cell_to_string/1)}",
          "",
          "Sample rows:"
        ] ++
          Enum.map(sample, fn row ->
            row |> Enum.map_join(" | ", &cell_to_string/1)
          end) ++
          [""]

      {:error, _reason} ->
        ["## Sheet: #{sheet_name}", "(could not read sheet)", ""]
    end
  end

  defp cell_to_string(nil), do: ""
  defp cell_to_string(value) when is_binary(value), do: value
  defp cell_to_string(value), do: to_string(value)

  defp split_text({:ok, text}) do
    pages =
      text
      |> String.split("\f")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.with_index(1)
      |> Enum.flat_map(fn {page, page_number} ->
        page
        |> chunk_page()
        |> Enum.with_index(1)
        |> Enum.map(fn {content, chunk_index} ->
          %{
            page_number: page_number,
            content: content,
            metadata: %{"chunk_index" => chunk_index}
          }
        end)
      end)

    # Scanned-image PDFs (phone-camera receipts saved as PDF) carry no text
    # layer, so pdftotext succeeds with empty output. Surface that as zero
    # pages so downstream classification can still run from filename and
    # attributes instead of leaving the document stuck as failed.
    {:ok, pages}
  end

  defp split_text({:error, reason}), do: {:error, reason}

  defp chunk_page(page) do
    page
    |> String.split("\n\n")
    |> Enum.reduce([""], fn paragraph, [current | rest] ->
      candidate = [current, paragraph] |> Enum.reject(&(&1 == "")) |> Enum.join("\n\n")

      if String.length(candidate) > @max_page_chars and current != "" do
        [paragraph, current | rest]
      else
        [candidate | rest]
      end
    end)
    |> Enum.reverse()
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp pdf?(content_type, filename),
    do: content_type == "application/pdf" or String.ends_with?(downcase(filename), ".pdf")

  defp docx?(content_type, filename) do
    content_type == "application/vnd.openxmlformats-officedocument.wordprocessingml.document" or
      String.ends_with?(downcase(filename), ".docx")
  end

  defp xlsx?(content_type, filename) do
    content_type == "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" or
      String.ends_with?(downcase(filename), ".xlsx")
  end

  defp text?(content_type, filename) do
    String.starts_with?(content_type || "", "text/") or
      String.ends_with?(downcase(filename), ".txt") or
      String.ends_with?(downcase(filename), ".md")
  end

  defp downcase(nil), do: ""
  defp downcase(value), do: String.downcase(value)
end
