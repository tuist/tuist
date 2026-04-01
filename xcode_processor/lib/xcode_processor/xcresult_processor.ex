defmodule XcodeProcessor.XCResultProcessor do
  @moduledoc false

  def process(storage_key) do
    bucket = XcodeProcessor.Environment.s3_bucket()
    temp_dir = make_temp_dir()
    zip_path = Path.join(temp_dir, "xcresult.zip")

    try do
      :telemetry.span([:xcode_processor, :xcresult], %{}, fn ->
        :telemetry.span([:xcode_processor, :s3, :download], %{}, fn ->
          {:ok, _} = ExAws.S3.download_file(bucket, storage_key, zip_path) |> ExAws.request()
          file_size = File.stat!(zip_path).size
          {:ok, %{file_size: file_size}}
        end)

        result = process_zip(zip_path, temp_dir)
        status = if match?({:ok, _}, result), do: :ok, else: :error
        {result, %{status: status}}
      end)
    after
      cleanup_temp(temp_dir)
    end
  end

  defp process_zip(zip_path, temp_dir) do
    {:ok, _} = :zip.unzip(~c"#{zip_path}", [{:cwd, ~c"#{temp_dir}"}])

    case find_xcresult(temp_dir) do
      nil ->
        {:error, :xcresult_not_found}

      xcresult_path ->
        root_dir = Path.dirname(xcresult_path)

        with {:ok, parsed_data} <- parse_xcresult(xcresult_path, root_dir) do
          quarantined_tests = read_quarantined_tests(xcresult_path)
          {:ok, apply_quarantine(parsed_data, quarantined_tests)}
        end
    end
  end

  defp parse_xcresult(xcresult_path, root_dir) do
    :telemetry.span([:xcode_processor, :xcresult, :parse], %{}, fn ->
      result = XcodeProcessor.XCResultNIF.parse(xcresult_path, root_dir)
      status = if match?({:ok, _}, result), do: :ok, else: :error
      {result, %{status: status}}
    end)
  end

  defp read_quarantined_tests(xcresult_path) do
    json_path = Path.join(xcresult_path, "quarantined_tests.json")

    case File.read(json_path) do
      {:ok, content} -> JSON.decode!(content)
      {:error, _} -> []
    end
  end

  defp apply_quarantine(parsed_data, []), do: parsed_data

  defp apply_quarantine(parsed_data, quarantined_tests) do
    test_modules =
      (parsed_data["test_modules"] || [])
      |> Enum.map(fn module ->
        test_cases =
          (module["test_cases"] || [])
          |> Enum.map(fn test_case ->
            is_quarantined =
              Enum.any?(quarantined_tests, fn q ->
                matches_quarantine?(test_case, module["name"], q)
              end)

            Map.put(test_case, "is_quarantined", is_quarantined)
          end)

        Map.put(module, "test_cases", test_cases)
      end)

    Map.put(parsed_data, "test_modules", test_modules)
  end

  defp matches_quarantine?(test_case, module_name, quarantined) do
    quarantined["target"] == module_name &&
      (is_nil(quarantined["class"]) || quarantined["class"] == test_case["test_suite_name"]) &&
      (is_nil(quarantined["method"]) || quarantined["method"] == test_case["name"])
  end

  defp make_temp_dir do
    temp_dir =
      Path.join(System.tmp_dir!(), "xcode_processor_#{:erlang.unique_integer([:positive])}")

    File.mkdir_p!(temp_dir)
    temp_dir
  end

  defp find_xcresult(temp_dir) do
    temp_dir
    |> Path.join("**/*.xcresult")
    |> Path.wildcard()
    |> List.first()
  end

  defp cleanup_temp(temp_dir) do
    {:ok, _} = File.rm_rf(temp_dir)
    :ok
  end
end
