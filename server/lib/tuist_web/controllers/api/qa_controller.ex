defmodule TuistWeb.API.QAController do
  use TuistWeb, :controller

  alias Tuist.QA
  alias Tuist.Storage
  alias TuistWeb.API.Authorization.AuthorizationPlug
  alias TuistWeb.Plugs.LoaderPlug

  plug LoaderPlug
  plug :load_qa_run
  plug AuthorizationPlug, :qa_step when action in [:create_step, :update_step]
  plug AuthorizationPlug, :qa_run when action in [:update_run]
  plug AuthorizationPlug, :qa_screenshot when action in [:create_screenshot]

  defp load_qa_run(%{assigns: %{selected_project: project}} = conn, _opts) do
    case conn.path_params do
      %{"qa_run_id" => run_id} ->
        case QA.qa_run(run_id, preload: [app_build: [preview: :project]]) do
          {:ok, qa_run} ->
            if qa_run.app_build.preview.project.id == project.id do
              assign(conn, :selected_qa_run, qa_run)
            else
              conn
              |> put_status(:not_found)
              |> json(%{error: "QA run not found"})
              |> halt()
            end

          {:error, :not_found} ->
            conn
            |> put_status(:not_found)
            |> json(%{error: "QA run not found"})
            |> halt()
        end

      _ ->
        conn
    end
  end

  def create_step(conn, %{"action" => action, "issues" => issues} = params) do
    %{selected_qa_run: qa_run} = conn.assigns

    result = Map.get(params, "result")

    attrs =
      then(
        %{qa_run_id: qa_run.id, action: action, issues: issues},
        &if(is_nil(result), do: &1, else: Map.put(&1, :result, result))
      )

    case QA.create_qa_step(attrs) do
      {:ok, qa_step} ->
        QA.update_screenshots_with_step_id(qa_run.id, qa_step.id)

        conn
        |> put_status(:created)
        |> json(%{
          id: qa_step.id,
          qa_run_id: qa_step.qa_run_id,
          action: qa_step.action,
          result: qa_step.result,
          issues: qa_step.issues,
          inserted_at: qa_step.inserted_at
        })

      {:error, changeset} ->
        message =
          changeset
          |> Ecto.Changeset.traverse_errors(fn {message, _opts} -> message end)
          |> Enum.flat_map(fn {_key, value} -> value end)
          |> Enum.join(", ")

        conn
        |> put_status(:bad_request)
        |> json(%{
          message: "QA step #{message}"
        })
    end
  end

  def update_step(%{assigns: %{selected_qa_run: qa_run}} = conn, %{"step_id" => step_id} = params) do
    with {:ok, qa_step} <- QA.step(step_id),
         true <- qa_step.qa_run_id == qa_run.id do
      update_attrs = %{
        result: Map.get(params, "result"),
        issues: Map.get(params, "issues", [])
      }

      case QA.update_step(qa_step, update_attrs) do
        {:ok, updated_qa_step} ->
          conn
          |> put_status(:ok)
          |> json(%{
            id: updated_qa_step.id,
            qa_run_id: updated_qa_step.qa_run_id,
            action: updated_qa_step.action,
            result: updated_qa_step.result,
            issues: updated_qa_step.issues,
            inserted_at: updated_qa_step.inserted_at
          })

        {:error, changeset} ->
          message =
            changeset
            |> Ecto.Changeset.traverse_errors(fn {message, _opts} -> message end)
            |> Enum.flat_map(fn {_key, value} -> value end)
            |> Enum.join(", ")

          conn
          |> put_status(:bad_request)
          |> json(%{
            message: "QA step #{message}"
          })
      end
    else
      false ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "QA step not found"})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "QA step not found"})
    end
  end

  def update_run(%{assigns: %{selected_qa_run: qa_run}} = conn, params) do
    update_attrs = %{}

    update_attrs =
      if Map.has_key?(params, "status") do
        Map.put(update_attrs, :status, params["status"])
      else
        update_attrs
      end

    update_attrs =
      if Map.has_key?(params, "status") and params["status"] in ["completed", "failed"] do
        Map.put(update_attrs, :finished_at, DateTime.utc_now())
      else
        update_attrs
      end

    case QA.update_qa_run(qa_run, update_attrs) do
      {:ok, updated_qa_run} ->
        conn
        |> put_status(:ok)
        |> json(%{
          id: updated_qa_run.id,
          status: updated_qa_run.status,
          updated_at: updated_qa_run.updated_at
        })

      {:error, changeset} ->
        message =
          changeset
          |> Ecto.Changeset.traverse_errors(fn {message, _opts} -> message end)
          |> Enum.flat_map(fn {_key, value} -> value end)
          |> Enum.join(", ")

        conn
        |> put_status(:bad_request)
        |> json(%{
          message: "QA step #{message}"
        })
    end
  end

  def create_screenshot(
        %{assigns: %{selected_qa_run: qa_run, selected_project: project}} = conn,
        %{"step_id" => step_id} = _params
      ) do
    attrs = %{
      qa_run_id: qa_run.id,
      qa_step_id: step_id
    }

    case QA.create_qa_screenshot(attrs) do
      {:ok, screenshot} ->
        expires_in = 3600

        storage_key =
          QA.screenshot_storage_key(%{
            account_handle: project.account.name,
            project_handle: project.name,
            qa_run_id: qa_run.id,
            screenshot_id: screenshot.id
          })

        upload_url =
          Storage.generate_upload_url(storage_key, project.account, expires_in: expires_in)

        conn
        |> put_status(:created)
        |> json(%{
          id: screenshot.id,
          qa_run_id: screenshot.qa_run_id,
          qa_step_id: screenshot.qa_step_id,
          inserted_at: screenshot.inserted_at,
          upload_url: upload_url,
          expires_at: System.system_time(:second) + expires_in
        })

      {:error, changeset} ->
        message =
          changeset
          |> Ecto.Changeset.traverse_errors(fn {message, _opts} -> message end)
          |> Enum.flat_map(fn {_key, value} -> value end)
          |> Enum.join(", ")

        conn
        |> put_status(:bad_request)
        |> json(%{
          message: "QA screenshot #{message}"
        })
    end
  end

  def start_recording_upload(%{assigns: %{selected_qa_run: qa_run, selected_project: project}} = conn, _params) do
    storage_key =
      QA.recording_storage_key(%{
        account_handle: project.account.name,
        project_handle: project.name,
        qa_run_id: qa_run.id
      })

    upload_id = Storage.multipart_start(storage_key, project.account)

    conn
    |> put_status(:created)
    |> json(%{
      upload_id: upload_id,
      storage_key: storage_key
    })
  end

  def generate_recording_upload_url(
        %{assigns: %{selected_project: project}} = conn,
        %{"upload_id" => upload_id, "part_number" => part_number, "storage_key" => storage_key} = params
      ) do
    expires_in = 120
    content_length = Map.get(params, "content_length")

    # Convert part_number to integer if it's a string
    part_number_int =
      case part_number do
        n when is_integer(n) -> n
        n when is_binary(n) -> String.to_integer(n)
      end

    # Convert content_length to integer if it's a string
    content_length_int =
      case content_length do
        nil -> nil
        n when is_integer(n) -> n
        n when is_binary(n) -> String.to_integer(n)
      end

    url =
      Storage.multipart_generate_url(
        storage_key,
        upload_id,
        part_number_int,
        project.account,
        expires_in: expires_in,
        content_length: content_length_int
      )

    json(conn, %{url: url})
  end

  def complete_recording_upload(%{assigns: %{selected_qa_run: qa_run, selected_project: project}} = conn, %{
        "upload_id" => upload_id,
        "storage_key" => storage_key,
        "parts" => parts,
        "started_at" => started_at,
        "duration" => duration
      }) do
    # Convert parts from maps to tuples for ExAws
    parts_tuples =
      Enum.map(parts, fn %{"part_number" => part_number, "etag" => etag} ->
        {part_number, etag}
      end)

    Storage.multipart_complete_upload(storage_key, upload_id, parts_tuples, project.account)

    # Parse started_at datetime
    {:ok, started_at_datetime, _} = DateTime.from_iso8601(started_at)

    # Create the recording
    case QA.create_qa_recording(%{
           qa_run_id: qa_run.id,
           started_at: started_at_datetime,
           duration: duration
         }) do
      {:ok, _recording} ->
        json(conn, %{status: "success"})

      {:error, changeset} ->
        message =
          changeset
          |> Ecto.Changeset.traverse_errors(fn {message, _opts} -> message end)
          |> Enum.flat_map(fn {_key, value} -> value end)
          |> Enum.join(", ")

        conn
        |> put_status(:bad_request)
        |> json(%{
          message: "Recording #{message}"
        })
    end
  end
end
