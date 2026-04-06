defmodule XcodeProcessor.Environment do
  @moduledoc false

  def webhook_secret do
    Application.get_env(:xcode_processor, :webhook_secret)
  end

  def s3_bucket do
    Application.get_env(:xcode_processor, :s3_bucket, "tuist")
  end
end
