defmodule XcodeProcessor.PromEx do
  @moduledoc false
  use PromEx, otp_app: :xcode_processor

  @impl true
  def plugins do
    [
      PromEx.Plugins.Beam,
      {PromEx.Plugins.Phoenix,
       router: XcodeProcessorWeb.Router,
       endpoint: XcodeProcessorWeb.Endpoint,
       duration_buckets: [10, 100, 500, 1000, 5000, 10_000, 30_000, 60_000, 120_000, 300_000]},
      XcodeProcessor.XCResultProcessing.PromExPlugin
    ]
  end
end
