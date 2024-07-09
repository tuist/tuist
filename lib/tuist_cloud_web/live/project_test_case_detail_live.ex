defmodule TuistCloudWeb.ProjectTestCaseDetailLive do
  alias TuistCloudWeb.Flop
  alias TuistCloud.CommandEvents
  use TuistCloudWeb, :live_view

  def mount(params, _session, socket) do
    uri =
      ("?" <> URI.encode_query(Map.take(params, ["after", "before"])))
      |> URI.new!()

    test_case_identifier =
      case Base.decode64(params["identifier"]) do
        {:ok, identifier} -> identifier
        _ -> raise TuistCloudWeb.Errors.NotFoundError, gettext("Invalid test case identifier")
      end

    test_case = CommandEvents.get_test_case_by_identifier(test_case_identifier)

    if is_nil(test_case) do
      raise TuistCloudWeb.Errors.NotFoundError, gettext("Test case not found")
    end

    {test_case_runs, test_case_runs_meta} =
      list_test_case_runs(test_case.id)

    {
      :ok,
      socket
      |> assign(:uri, uri)
      |> assign(:test_case, test_case)
      |> assign(:test_case_runs, test_case_runs)
      |> assign(:test_case_runs_meta, test_case_runs_meta)
    }
  end

  def handle_params(
        params,
        _uri,
        %{assigns: %{test_case: test_case}} = socket
      ) do
    {next_test_case_runs, next_test_case_runs_meta} =
      list_test_case_runs(test_case.id, before: params["before"], after: params["after"])

    {
      :noreply,
      socket
      |> assign(:test_case_runs, next_test_case_runs)
      |> assign(:test_case_runs_meta, next_test_case_runs_meta)
    }
  end

  defp list_test_case_runs(test_case_id, attrs \\ []) do
    options =
      %{
        filters: [%{field: :test_case_id, op: :==, value: test_case_id}],
        order_by: [:inserted_at],
        order_directions: [:desc]
      }
      |> Flop.get_options_with_before_and_after(attrs)

    CommandEvents.list_test_case_runs(options)
  end
end
