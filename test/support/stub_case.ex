defmodule Tuist.StubCase do
  @moduledoc ~S"""
  This module shares common setup for stubbing core services like the billing logic.
  """
  use ExUnit.CaseTemplate

  using options do
    quote do
      use Mimic

      if unquote(options)[:billing] do
        setup do
          Tuist.Billing |> stub(:create_customer, fn _ -> "cust_#{UUIDv7.generate()}" end)
          Tuist.Billing |> stub(:start_trial, fn _ -> :ok end)
          :ok
        end
      end
    end
  end
end
