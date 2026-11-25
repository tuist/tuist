defmodule Atlas.Documents.TextExtractor do
  @moduledoc false

  @max_page_chars 12_000
  @xlsx_sample_rows 20
  # Bounds for archives: entries are extracted in memory, so cap how many and
  # how many declared bytes are read (the document library's upload cap).
  @max_zip_entries 20
  @max_zip_bytes 50 * 1024 * 1024

  def extract_pages(path, content_type, filename, opts \\ []) do
    cond do
      pdf?(content_type, filename) ->
        extract_pdf(path, opts)

      docx?(content_type, filename) ->
        extract_docx(path)

      xlsx?(content_type, filename) ->
        extract_xlsx(path, filename)

      text?(content_type, filename) ->
        path |> File.read() |> split_text()

      zip?(content_type, filename) and Keyword.get(opts, :archives?, true) ->
        extract_zip(path, opts)

      true ->
        {:error, :unsupported_document_type}
    end
  end

  defp extract_pdf(path, opts) do
    case System.find_executable("pdftotext") do
      nil ->
        {:error, :pdftotext_not_found}

      executable ->
        # Briefly removes the temp file when this process exits, so there is no
        # manual cleanup. MuonTrap.cmd propagates kills to pdftotext if the
        # owning process dies mid-extraction.
        with {:ok, output_path} <- Briefly.create(),
             {_output, 0} <-
               MuonTrap.cmd(
                 executable,
                 pdf_args(path, output_path, opts),
                 Keyword.put(Keyword.take(opts, [:timeout]), :stderr_to_stdout, true)
               ),
             :ok <- check_pdf_text_size(output_path, opts),
             {:ok, text} <- File.read(output_path) do
          split_text({:ok, text})
        else
          {output, _exit_status} when is_binary(output) -> {:error, :pdf_text_extraction_failed}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp pdf_args(path, output_path, opts) do
    pages =
      case Keyword.get(opts, :max_pages) do
        nil -> []
        limit -> ["-f", "1", "-l", Integer.to_string(limit)]
      end

    ["-layout"] ++ pages ++ [path, output_path]
  end

  defp check_pdf_text_size(path, opts) do
    with max when is_integer(max) <- Keyword.get(opts, :max_text_bytes),
         {:ok, %{size: size}} when size > max <- File.stat(path) do
      {:error, :pdf_text_too_large}
    else
      _ -> :ok
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

  # A zip (for example a contract package sent by email) is indexed by the
  # text of the supported files it contains, one after another. Each page
  # records the entry it came from. Unsupported or unreadable entries are
  # skipped, and an archive with none still completes with zero pages so the
  # stored zip stays available for download instead of failing.
  defp extract_zip(path, opts) do
    with {:ok, entries} <- :zip.list_dir(String.to_charlist(path)),
         names = zip_entry_names(entries),
         {:ok, files} <- zip_entries(path, names) do
      pages =
        files
        |> Enum.sort_by(fn {name, _body} -> name end)
        |> Enum.flat_map(&zip_entry_pages(&1, opts))
        |> Enum.with_index(1)
        |> Enum.map(fn {page, page_number} -> %{page | page_number: page_number} end)

      {:ok, pages}
    else
      {:error, {:invalid, _reason}} = error -> error
      {:error, _reason} -> {:error, :zip_extraction_failed}
    end
  end

  defp zip_entry_names(entries) do
    entries
    |> Enum.flat_map(fn
      {:zip_file, name, info, _comment, _offset, _compressed} ->
        name = List.to_string(name)
        if supported_zip_entry?(name), do: [{name, elem(info, 1)}], else: []

      _other ->
        []
    end)
    |> Enum.take(@max_zip_entries)
  end

  defp zip_entries(_path, []), do: {:ok, []}

  defp zip_entries(path, entries) do
    if Enum.sum_by(entries, fn {_name, size} -> size end) > @max_zip_bytes do
      {:error, {:invalid, :zip_too_large}}
    else
      file_list = Enum.map(entries, fn {name, _size} -> String.to_charlist(name) end)

      case :zip.extract(String.to_charlist(path), [:memory, {:file_list, file_list}]) do
        {:ok, files} -> {:ok, Enum.map(files, fn {name, body} -> {List.to_string(name), body} end)}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp supported_zip_entry?(name) do
    basename = Path.basename(name)

    not String.ends_with?(name, "/") and not String.starts_with?(name, "__MACOSX/") and
      not String.starts_with?(basename, ".") and
      String.downcase(Path.extname(name)) in ~w(.pdf .docx .xlsx .txt .md)
  end

  defp zip_entry_pages({name, body}, opts) do
    with {:ok, entry_path} <- Briefly.create(extname: Path.extname(name)),
         :ok <- File.write(entry_path, body),
         {:ok, pages} <- extract_pages(entry_path, nil, name, Keyword.put(opts, :archives?, false)) do
      Enum.map(pages, fn page -> %{page | metadata: Map.put(page.metadata, "archive_entry", name)} end)
    else
      _error -> []
    end
  end

  defp cell_to_string(nil), do: ""
  defp cell_to_string(value) when is_binary(value), do: value
  defp cell_to_string(value), do: to_string(value)

  # Every chunk is stored as its own page row, and page numbers are unique per
  # document, so chunks are numbered in order and keep the page they came from
  # in `source_page`. DOCX text has no page breaks and is one long page.
  defp split_text({:ok, text}) do
    pages =
      text
      |> String.split("\f")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.with_index(1)
      |> Enum.flat_map(fn {page, source_page} ->
        page
        |> chunk_page()
        |> Enum.with_index(1)
        |> Enum.map(fn {content, chunk_index} ->
          %{content: content, metadata: %{"source_page" => source_page, "chunk_index" => chunk_index}}
        end)
      end)
      |> Enum.with_index(1)
      |> Enum.map(fn {page, page_number} -> Map.put(page, :page_number, page_number) end)

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

  defp zip?(content_type, filename) do
    content_type in ~w(application/zip application/x-zip-compressed application/x-zip) or
      String.ends_with?(downcase(filename), ".zip")
  end

  defp downcase(nil), do: ""
  defp downcase(value), do: String.downcase(value)
end
