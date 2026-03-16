defmodule Processor.PromEx do
  @moduledoc false
  use PromEx, otp_app: :processor

  @impl true
  def plugins do
    [
      PromEx.Plugins.Beam,
      {PromEx.Plugins.Phoenix,
       router: ProcessorWeb.Router,
       endpoint: ProcessorWeb.Endpoint,
       duration_buckets: [10, 100, 500, 1000, 5000, 10_000, 30_000, 60_000, 120_000, 300_000]},
      Processor.BuildProcessing.PromExPlugin
    ]
  end
end
