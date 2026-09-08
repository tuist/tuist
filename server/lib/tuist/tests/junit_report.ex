defmodule Tuist.Tests.JunitReport do
  @moduledoc false

  alias Tuist.Tests.Sanitizer

  @max_report_bytes 5 * 1_024 * 1_024
  @max_test_cases 10_000
  @max_field_bytes 1_024
  @max_failure_message_bytes 8 * 1_024

  def parse(report) when is_binary(report) and byte_size(report) <= @max_report_bytes do
    with :ok <- reject_unsafe_document(report),
         {:ok, document} <- Saxy.SimpleForm.parse_string(report, expand_entity: :skip) do
      test_suites = elements_named(document, "testsuite")

      test_cases =
        test_suites
        |> Enum.flat_map(&test_cases_for_suite/1)
        |> Enum.take(@max_test_cases)

      {:ok, %{test_suites: suites_for(test_suites, test_cases), test_cases: test_cases}}
    else
      {:error, _reason} -> {:error, :invalid_report}
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

  defp elements_named({tag, _attributes, children} = element, name) do
    current = if local_name(tag) == name, do: [element], else: []

    current ++
      Enum.flat_map(children, fn
        {_tag, _attributes, _children} = child -> elements_named(child, name)
        _text -> []
      end)
  end

  defp test_cases_for_suite(test_suite) do
    suite_name = attribute(test_suite, "name") || "Unnamed suite"

    test_suite
    |> child_elements("testcase")
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
    failure_nodes = child_elements(test_case, "failure") ++ child_elements(test_case, "error")

    cond do
      failure_nodes != [] ->
        {"failure", Enum.map(failure_nodes, &failure/1)}

      child_elements(test_case, "skipped") != [] ->
        {"skipped", []}

      true ->
        {"success", []}
    end
  end

  defp failure(failure) do
    message =
      failure
      |> attribute("message")
      |> Kernel.||(failure |> text_content() |> String.trim())
      |> Sanitizer.sanitize()

    %{
      message: truncate(message, @max_failure_message_bytes),
      path:
        failure
        |> attribute("file")
        |> Kernel.||("")
        |> Sanitizer.sanitize()
        |> truncate(@max_field_bytes),
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

  defp child_elements({_tag, _attributes, children}, name) do
    Enum.filter(children, fn
      {tag, _attributes, _children} -> local_name(tag) == name
      _text -> false
    end)
  end

  defp attribute({_tag, attributes, _children}, name) do
    attributes
    |> Enum.find_value(fn {attribute_name, value} ->
      if local_name(attribute_name) == name, do: value
    end)
    |> case do
      nil -> nil
      value -> value |> String.trim() |> truncate(@max_field_bytes) |> empty_to_nil()
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

  defp text_content({_tag, _attributes, children}) do
    Enum.map_join(children, fn
      text when is_binary(text) -> text
      {:cdata, text} -> text
      {_tag, _attributes, _children} = child -> text_content(child)
    end)
  end

  defp local_name(name), do: name |> String.split(":") |> List.last()
  defp empty_to_nil(""), do: nil
  defp empty_to_nil(value), do: value

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
