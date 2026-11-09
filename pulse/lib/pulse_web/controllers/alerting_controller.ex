defmodule PulseWeb.AlertingController do
  use PulseWeb, :controller

  alias Pulse.Alerting
  alias Pulse.Alerting.{Evaluator, Principal}
  alias Pulse.Alerting.Importer
  alias Pulse.Alerting.RuleFiles

  def index(conn, _params), do: run(conn, fn actor -> Alerting.list(actor) end)

  def import_preview(conn, params) do
    run(conn, fn actor ->
      with :ok <- Principal.authorize(actor, "alert:import"),
           {:ok, reports} <- Importer.preview(params["rules"]),
           do: {:ok, %{"rules" => reports}}
    end)
  end

  def import_rule_file_preview(conn, params) do
    run(conn, fn actor ->
      with :ok <- Principal.authorize(actor, "alert:import"),
           :ok <- Principal.authorize(actor, "alert:record"),
           do: RuleFiles.preview(params["content"])
    end)
  end

  def show(conn, %{"id" => id}), do: run(conn, fn actor -> Alerting.get(actor, id) end)
  def state(conn, %{"id" => id}), do: run(conn, fn actor -> Alerting.state(actor, id) end)
  def preview(conn, %{"id" => id}), do: run(conn, fn actor -> Evaluator.preview(actor, id) end)
  def evaluate(conn, %{"id" => id}), do: run(conn, fn actor -> Evaluator.evaluate(actor, id) end)

  def create(conn, %{"id" => id} = params), do: mutation(conn, id, params, &Alerting.create/3)
  def update(conn, %{"id" => id} = params), do: mutation(conn, id, params, &Alerting.update/3)
  def delete(conn, %{"id" => id} = params), do: mutation(conn, id, params, &Alerting.delete/3)
  def restore(conn, %{"id" => id} = params), do: mutation(conn, id, params, &Alerting.restore/3)

  def changes(conn, %{"id" => id} = params) do
    run(conn, fn actor ->
      if conn.method == "GET" and Map.has_key?(params, "cursor") do
        {:error, :invalid_arguments}
      else
        Alerting.changes(actor, id, pagination(params))
      end
    end)
  end

  def events(conn, %{"id" => id} = params) do
    run(conn, fn actor -> Alerting.events(actor, id, pagination(params)) end)
  end

  def revision(conn, %{"id" => id, "revision" => revision} = params) do
    run(conn, fn actor ->
      if conn.method == "GET" and Map.has_key?(params, "revision_cursor"),
        do: {:error, :invalid_arguments},
        else:
          Alerting.historical(
            actor,
            id,
            Map.take(Map.put(params, "revision", revision), ["revision", "revision_cursor"])
          )
    end)
  end

  defp mutation(conn, id, params, fun) do
    run(conn, fn actor ->
      params = Map.delete(params, "id")

      with {:ok, params} <- precondition(get_req_header(conn, "if-match"), params),
           do: fun.(actor, id, params)
    end)
  end

  defp precondition([], params), do: {:ok, params}

  defp precondition([value], params) do
    expected = String.trim(value, "\"")

    if params["expected_revision"] in [nil, expected],
      do: {:ok, Map.put(params, "expected_revision", expected)},
      else: {:error, :conflict}
  end

  defp precondition(_, _), do: {:error, :invalid_arguments}

  defp pagination(params) do
    params = Map.take(params, ["cursor", "limit"])

    case params["limit"] do
      value when is_binary(value) ->
        case Integer.parse(value) do
          {number, ""} -> Map.put(params, "limit", number)
          _ -> params
        end

      _ ->
        params
    end
  end

  defp run(conn, fun) do
    tenant =
      case get_req_header(conn, "x-scope-orgid") do
        [] -> "default"
        [tenant] -> tenant
        _ -> nil
      end

    with {:ok, actor} <- Principal.authenticate(conn, tenant), {:ok, data} <- fun.(actor) do
      conn =
        if is_map(data) and is_binary(data["revision"]),
          do: put_resp_header(conn, "etag", "\"#{data["revision"]}\""),
          else: conn

      json(conn, data)
    else
      {:error, reason} -> error(conn, reason)
    end
  end

  defp error(conn, reason) do
    {status, code} = error_status(reason)
    conn = if status == 429 or reason == :evaluation_skipped, do: put_resp_header(conn, "retry-after", "1"), else: conn
    conn |> put_status(status) |> json(%{"error" => code})
  end

  defp error_status({:graph_source, _, _}), do: {422, "unsupported_graph_source"}
  defp error_status({:expression_node, _, _}), do: {422, "unsupported_expression"}

  defp error_status(reason)
       when reason in [:invalid_expression_graph, :unsupported_series_math, :expression_label_loss],
       do: {422, "unsupported_expression"}

  defp error_status(:evaluation_skipped), do: {503, "evaluation_skipped"}
  defp error_status(:query_overloaded), do: {429, "query_overloaded"}
  defp error_status(reason) when reason in [:query_timeout, :expression_timeout], do: {504, Atom.to_string(reason)}

  defp error_status(reason)
       when reason in [
              :query_scan_limit,
              :query_sample_limit,
              :query_work_limit,
              :query_result_limit,
              :query_intermediate_limit,
              :query_resource_limit,
              :expression_input_limit,
              :expression_work_limit,
              :expression_result_limit,
              :query_expression_limit,
              :many_to_many_matching,
              :duplicate_result_label_sets,
              :invalid_aggregation_parameter,
              :invalid_duration,
              :invalid_range_or_too_many_steps,
              :invalid_timestamp,
              :nonfinite_result,
              :non_finite_sample_value,
              :unsupported_sample_value,
              :invalid_stored_sample,
              :pipeline_error,
              :sample_extraction_error
            ], do: {422, Atom.to_string(reason)}

  defp error_status(reason)
       when reason in [
              :invalid_or_unsupported_query,
              :invalid_range,
              :invalid_operand,
              :invalid_function_arguments,
              :invalid_aggregation,
              :invalid_binary_expression,
              :invalid_grouping,
              :invalid_subquery,
              :invalid_label_replace,
              :invalid_selector,
              :invalid_evaluation_time_or_step,
              :invalid_query_batch,
              :invalid_query_result,
              :invalid_logql,
              :unsupported_source_query
            ], do: {422, "unsupported_source_query"}

  defp error_status(:invalid_source_bindings), do: {500, "invalid_source_bindings"}

  defp error_status(reason) do
    case reason do
      :unauthorized ->
        {401, "unauthorized"}

      :forbidden ->
        {403, "forbidden"}

      :not_found ->
        {404, "not_found"}

      reason when reason in [:conflict, :operation_reused, :not_due, :stale_evaluation] ->
        {409, Atom.to_string(reason)}

      reason when reason in [:invalid_arguments, :invalid_rule, :invalid_id, :invalid_import, :duplicate_rule_id] ->
        {400, Atom.to_string(reason)}

      reason when reason in [:reset_required, :invalid_or_expired_position] ->
        {409, Atom.to_string(reason)}

      reason when reason in [:rule_disabled, :unsupported_rule] ->
        {422, Atom.to_string(reason)}

      _ ->
        {503, "alerting_unavailable"}
    end
  end
end
