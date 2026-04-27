defmodule XcodeProcessor.Environment do
  @moduledoc false

  def webhook_secret do
    case Application.get_env(:xcode_processor, :webhook_secret) do
      nil -> nil
      value when is_binary(value) -> String.trim(value)
    end
  end

  def s3_bucket do
    Application.get_env(:xcode_processor, :s3_bucket, "tuist")
  end
end
