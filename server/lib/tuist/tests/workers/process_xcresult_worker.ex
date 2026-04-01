defmodule Tuist.Tests.Workers.ProcessXcresultWorker do
  @moduledoc false
  use Oban.Worker, queue: :default, max_attempts: 3, unique: [keys: [:test_run_id]]

  alias Tuist.Accounts
  alias Tuist.Storage
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

    result =
      if is_nil(xcode_processor_url) or xcode_processor_url == "" do
        process_locally(test_run_id, storage_key, account_id, args)
      else
        send_to_xcode_processor(xcode_processor_url, test_run_id, storage_key, args)
      end

    case result do
      {:ok, parsed_data} ->
        replace_test_run(parsed_data, args)

      {:error, reason} ->
        if attempt >= max_attempts do
          Logger.error(
            "Failed to process xcresult for test run #{test_run_id} after #{max_attempts} attempts: #{inspect(reason)}"
          )

          mark_failed_processing(args)
        end

        {:error, reason}
    end
  end

  defp process_locally(test_run_id, storage_key, account_id, args) do
    with {:ok, account} <- Accounts.get_account_by_id(account_id) do
      temp_path = Path.join(System.tmp_dir!(), "xcresult_#{test_run_id}.zip")

      try do
        case Storage.download_to_file(storage_key, temp_path, account) do
          {:ok, _} ->
            opts = [
              test_run_id: test_run_id,
              account_handle: args["account_handle"],
              project_handle: args["project_handle"]
            ]

            XcodeProcessor.XCResultProcessor.process_local(temp_path, opts)

          {:error, _} = error ->
            error
        end
      after
        File.rm(temp_path)
      end
    end
  end

  defp send_to_xcode_processor(xcode_processor_url, test_run_id, storage_key, args) do
    webhook_secret = Tuist.Environment.xcode_processor_webhook_secret()

    if is_nil(webhook_secret) or webhook_secret == "" do
      Logger.error("Xcode processor webhook secret not configured for test run #{test_run_id}")
      {:error, "webhook_secret_not_configured"}
    else
      payload = %{
        test_run_id: test_run_id,
        storage_key: storage_key,
        account_id: args["account_id"],
        project_id: args["project_id"],
        account_handle: args["account_handle"],
        project_handle: args["project_handle"]
      }

      json_body = JSON.encode!(payload)

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

  defp replace_test_run(parsed_data, args) do
    attrs =
      Map.merge(base_attrs(args), %{
        test_plan_name: parsed_data["test_plan_name"],
        status: parsed_data["status"] || "success",
        duration: parsed_data["duration"] || 0,
        test_modules: parsed_data["test_modules"] || []
      })

    case Tests.create_test(attrs) do
      {:ok, _} -> :ok
      error -> error
    end
  end

  defp mark_failed_processing(args) do
    attrs =
      Map.merge(base_attrs(args), %{
        status: "failed_processing",
        duration: 0,
        test_modules: []
      })

    case Tests.create_test(attrs) do
      {:ok, _} -> :ok
      error -> error
    end
  end

  defp base_attrs(args) do
    %{
      id: args["test_run_id"],
      project_id: args["project_id"],
      account_id: args["account_id"],
      is_ci: Map.get(args, "is_ci", false),
      git_branch: Map.get(args, "git_branch"),
      git_commit_sha: Map.get(args, "git_commit_sha"),
      git_ref: Map.get(args, "git_ref"),
      macos_version: Map.get(args, "macos_version"),
      xcode_version: Map.get(args, "xcode_version"),
      model_identifier: Map.get(args, "model_identifier"),
      scheme: Map.get(args, "scheme"),
      ci_run_id: Map.get(args, "ci_run_id"),
      ci_host: Map.get(args, "ci_host"),
      ci_provider: Map.get(args, "ci_provider"),
      ran_at: NaiveDateTime.utc_now()
    }
  end
end
