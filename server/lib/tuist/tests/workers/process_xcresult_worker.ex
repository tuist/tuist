defmodule Tuist.Tests.Workers.ProcessXcresultWorker do
  @moduledoc false
  use Oban.Worker, queue: :default, max_attempts: 3, unique: [keys: [:test_run_id]]

  alias Tuist.Tests

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{
        args:
          %{
            "test_run_id" => test_run_id,
            "storage_key" => storage_key,
            "account_id" => account_id,
            "project_id" => project_id
          } = args,
        attempt: attempt,
        max_attempts: max_attempts
      }) do
    xcode_processor_url = Tuist.Environment.xcode_processor_url()

    if is_nil(xcode_processor_url) or xcode_processor_url == "" do
      Logger.debug("Xcode processor URL not configured, skipping xcresult processing for test run #{test_run_id}")
      :ok
    else
      result =
        send_to_xcode_processor(xcode_processor_url, test_run_id, storage_key, account_id, project_id)

      case result do
        {:ok, parsed_data} ->
          create_test_from_parsed_data(parsed_data, args)

        {:error, reason} ->
          if attempt >= max_attempts do
            Logger.error("Failed to process xcresult for test run #{test_run_id} after #{max_attempts} attempts: #{inspect(reason)}")
            mark_failed_processing(args)
          end

          {:error, reason}
      end
    end
  end

  defp send_to_xcode_processor(xcode_processor_url, test_run_id, storage_key, account_id, project_id) do
    webhook_secret = Tuist.Environment.xcode_processor_webhook_secret()

    if is_nil(webhook_secret) or webhook_secret == "" do
      Logger.error("Xcode processor webhook secret not configured for test run #{test_run_id}")
      {:error, "webhook_secret_not_configured"}
    else
      payload = %{
        test_run_id: test_run_id,
        storage_key: storage_key,
        account_id: account_id,
        project_id: project_id
      }

      json_body = Jason.encode!(payload)

      signature =
        :hmac
        |> :crypto.mac(:sha256, webhook_secret, json_body)
        |> Base.encode16(case: :lower)

      case Req.post("#{xcode_processor_url}/webhooks/process-xcresult",
             body: json_body,
             headers: [
               {"content-type", "application/json"},
               {"x-webhook-signature", signature}
             ],
             receive_timeout: 300_000
           ) do
        {:ok, %{status: 200, body: parsed_data}} ->
          {:ok, parsed_data}

        {:ok, %{status: status, body: body}} ->
          Logger.error("Xcode processor returned #{status} for test run #{test_run_id}: #{inspect(body)}")
          {:error, "xcode_processor_error_#{status}: #{inspect(body)}"}

        {:error, reason} ->
          Logger.error("Xcode processor request failed for test run #{test_run_id}: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  defp create_test_from_parsed_data(parsed_data, args) do
    test_modules = build_test_modules(parsed_data)

    attrs = %{
      id: args["test_run_id"],
      project_id: args["project_id"],
      account_id: args["account_id"],
      test_plan_name: parsed_data["test_plan_name"],
      status: normalize_status(parsed_data["status"]),
      duration: parsed_data["duration"] || 0,
      test_modules: test_modules,
      is_ci: Map.get(args, "is_ci", false),
      git_branch: Map.get(args, "git_branch"),
      git_commit_sha: Map.get(args, "git_commit_sha"),
      git_ref: Map.get(args, "git_ref"),
      macos_version: Map.get(args, "macos_version"),
      xcode_version: Map.get(args, "xcode_version"),
      model_identifier: Map.get(args, "model_identifier"),
      scheme: Map.get(args, "scheme"),
      ran_at: NaiveDateTime.utc_now()
    }

    Tests.create_test(attrs)
  end

  defp mark_failed_processing(args) do
    attrs = %{
      id: args["test_run_id"],
      project_id: args["project_id"],
      account_id: args["account_id"],
      status: "failed_processing",
      duration: 0,
      test_modules: [],
      is_ci: Map.get(args, "is_ci", false),
      git_branch: Map.get(args, "git_branch"),
      git_commit_sha: Map.get(args, "git_commit_sha"),
      git_ref: Map.get(args, "git_ref"),
      macos_version: Map.get(args, "macos_version"),
      xcode_version: Map.get(args, "xcode_version"),
      model_identifier: Map.get(args, "model_identifier"),
      scheme: Map.get(args, "scheme"),
      ran_at: NaiveDateTime.utc_now()
    }

    Tests.create_test(attrs)
  end

  defp normalize_status("passed"), do: "success"
  defp normalize_status("failed"), do: "failure"
  defp normalize_status("skipped"), do: "skipped"
  defp normalize_status("success"), do: "success"
  defp normalize_status(nil), do: "success"
  defp normalize_status(_other), do: "failure"

  defp build_test_modules(parsed_data) do
    for module <- parsed_data["test_modules"] || [] do
      %{
        name: module["name"],
        status: normalize_status(module["status"]),
        duration: module["duration"] || 0,
        test_suites:
          for suite <- module["test_suites"] || [] do
            %{
              name: suite["name"],
              status: normalize_status(suite["status"]),
              duration: suite["duration"] || 0
            }
          end,
        test_cases:
          for test_case <- module["test_cases"] || [] do
            %{
              name: test_case["name"],
              test_suite: test_case["test_suite"],
              status: normalize_status(test_case["status"]),
              duration: test_case["duration"] || 0,
              failures:
                for failure <- test_case["failures"] || [] do
                  %{
                    message: failure["message"],
                    file: failure["path"],
                    line_number: failure["line_number"],
                    issue_type: failure["issue_type"]
                  }
                end,
              repetitions:
                for rep <- test_case["repetitions"] || [] do
                  %{
                    repetition_number: rep["repetition_number"],
                    name: rep["name"],
                    status: normalize_status(rep["status"]),
                    duration: rep["duration"] || 0,
                    failures:
                      for failure <- rep["failures"] || [] do
                        %{
                          message: failure["message"],
                          file: failure["path"],
                          line_number: failure["line_number"],
                          issue_type: failure["issue_type"]
                        }
                      end
                  }
                end
            }
          end
      }
    end
  end
end
