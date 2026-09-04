defmodule Tuist.Bazel.JunitReport do
  @moduledoc false

  import SweetXml

  @max_report_bytes 5 * 1024 * 1024
  @max_test_cases 10_000
  @max_field_bytes 1_024
  @max_failure_message_bytes 8 * 1_024

  def parse(report) when is_binary(report) and byte_size(report) <= @max_report_bytes do
    with :ok <- reject_unsafe_document(report),
         {:ok, document} <- parse_document(report) do
      test_suites = xpath(document, ~x"//testsuite"l)

      test_cases =
        test_suites
        |> Enum.flat_map(&test_cases_for_suite/1)
        |> Enum.take(@max_test_cases)

      {:ok, %{test_suites: suites_for(test_suites, test_cases), test_cases: test_cases}}
    end
  end

  def parse(_), do: {:error, :invalid_report}

  defp reject_unsafe_document(report) do
    if Regex.match?(~r/<\s*!DOCTYPE|<\s*!ENTITY/i, report) do
      {:error, :unsafe_document}
    else
      :ok
    end
  end

  defp parse_document(report) do
    {:ok, SweetXml.parse(report, quiet: true)}
  rescue
    _ -> {:error, :invalid_report}
  end

  defp test_cases_for_suite(test_suite) do
    suite_name = attribute(test_suite, "name") || "Unnamed suite"

    test_suite
    |> xpath(~x"./testcase"l)
    |> Enum.map(fn test_case ->
      {status, failures} = status_and_failures(test_case)

      %{
        name: attribute(test_case, "name") || "Unnamed test",
        test_suite_name: suite_name,
        status: status,
        duration: duration_milliseconds(test_case),
        failures: failures
      }
    end)
  end

  defp suites_for(test_suites, test_cases) do
    case_names = MapSet.new(Enum.map(test_cases, & &1.test_suite_name))

    test_suites
    |> Enum.map(&attribute(&1, "name"))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.filter(&MapSet.member?(case_names, &1))
    |> Enum.map(fn name ->
      suite_test_cases = Enum.filter(test_cases, &(&1.test_suite_name == name))

      %{
        name: name,
        status: aggregate_status(suite_test_cases),
        duration: Enum.sum(Enum.map(suite_test_cases, & &1.duration))
      }
    end)
  end

  defp status_and_failures(test_case) do
    failure_nodes = xpath(test_case, ~x"./failure"l) ++ xpath(test_case, ~x"./error"l)

    cond do
      failure_nodes != [] ->
        {"failure", Enum.map(failure_nodes, &failure/1)}

      xpath(test_case, ~x"./skipped"l) != [] ->
        {"skipped", []}

      true ->
        {"success", []}
    end
  end

  defp failure(failure) do
    message =
      attribute(failure, "message") ||
        failure
        |> xpath(~x"string(.)"s)
        |> to_string()
        |> String.trim()

    %{
      message: truncate(message, @max_failure_message_bytes),
      path: attribute(failure, "file") || "",
      line_number: integer_attribute(failure, "line") || 0,
      issue_type: "assertion_failure"
    }
  end

  defp aggregate_status(test_cases) do
    cond do
      Enum.any?(test_cases, &(&1.status == "failure")) -> "failure"
      test_cases != [] and Enum.all?(test_cases, &(&1.status == "skipped")) -> "skipped"
      true -> "success"
    end
  end

  defp duration_milliseconds(test_case) do
    value = attribute(test_case, "time") || attribute(test_case, "duration") || "0"

    case Float.parse(value) do
      {seconds, ""} when seconds >= 0 -> min(round(seconds * 1_000), 2_147_483_647)
      _ -> 0
    end
  end

  defp attribute(element, "name"), do: xpath_attribute(element, ~x"string(./@name)"s)
  defp attribute(element, "time"), do: xpath_attribute(element, ~x"string(./@time)"s)
  defp attribute(element, "duration"), do: xpath_attribute(element, ~x"string(./@duration)"s)
  defp attribute(element, "message"), do: xpath_attribute(element, ~x"string(./@message)"s)
  defp attribute(element, "file"), do: xpath_attribute(element, ~x"string(./@file)"s)
  defp attribute(element, "line"), do: xpath_attribute(element, ~x"string(./@line)"s)

  defp xpath_attribute(element, xpath) do
    element
    |> xpath(xpath)
    |> to_string()
    |> String.trim()
    |> truncate(@max_field_bytes)
    |> case do
      "" -> nil
      value -> value
    end
  end

  defp integer_attribute(element, name) do
    case attribute(element, name) do
      nil ->
        nil

      value ->
        case Integer.parse(value) do
          {integer, ""} when integer >= 0 -> integer
          _ -> nil
        end
    end
  end

  defp truncate(value, max_bytes) when is_binary(value) do
    value
    |> String.graphemes()
    |> Enum.reduce_while({[], 0}, fn grapheme, {graphemes, byte_count} ->
      grapheme_size = byte_size(grapheme)

      if byte_count + grapheme_size <= max_bytes do
        {:cont, {[grapheme | graphemes], byte_count + grapheme_size}}
      else
        {:halt, {graphemes, byte_count}}
      end
    end)
    |> then(fn {graphemes, _} -> graphemes |> Enum.reverse() |> IO.iodata_to_binary() end)
  end
end
