defmodule Atlas.TestSupport.ScreenshotNoteAgent do
  @moduledoc false

  alias Atlas.TestSupport.ProcessRegistry

  def put_response(response) do
    ProcessRegistry.put({__MODULE__, :draft_note_from_screenshots}, response)
  end

  def put_response(account_id, response) when is_binary(account_id) do
    ProcessRegistry.put({__MODULE__, :draft_note_from_screenshots, account_id}, response)
  end

  def draft_note_from_screenshots(screenshots, %{id: account_id} = context) when is_binary(account_id) do
    case ProcessRegistry.get({__MODULE__, :draft_note_from_screenshots, account_id}) do
      nil -> draft_note_from_owner_response(screenshots, context)
      callback when is_function(callback, 2) -> callback.(screenshots, context)
      response -> response
    end
  end

  def draft_note_from_screenshots(screenshots, context) do
    draft_note_from_owner_response(screenshots, context)
  end

  defp draft_note_from_owner_response(screenshots, context) do
    case ProcessRegistry.get({__MODULE__, :draft_note_from_screenshots}) do
      nil -> {:error, :llm_not_configured}
      callback when is_function(callback, 2) -> callback.(screenshots, context)
      response -> response
    end
  end
end
