defmodule Tuist.Analytics.AttionTest do
  alias Tuist.Environment
  alias Tuist.Analytics.Attio
  use ExUnit.Case, async: true
  use Mimic

  describe "process_event/2" do
    test "when organization_create" do
      # Given
      organization_name = "tuist"
      email = "test@tuist.io"
      table_id = "table_id"
      process_name = "attio"
      company_id = %{"object_id" => "1234", "record_id" => "5678"}
      api_key = "api_key"

      Req
      |> expect(:put, fn _req, opts ->
        assert Keyword.get(opts, :url) ==
                 "/v2/objects/companies/records?matching_attribute=domains"

        assert Keyword.get(opts, :json) == %{
                 data: %{
                   values: %{
                     name: [%{value: organization_name}],
                     domains: [%{domain: "#{organization_name}.cloud.tuist.io"}]
                   }
                 }
               }

        assert Keyword.get(opts, :headers) == [
                 {"content-type", "application/json"},
                 {"authorization", "Bearer #{api_key}"}
               ]

        {:ok, %{body: %{"data" => %{"id" => company_id}}}}
      end)
      |> expect(:put, fn _req, opts ->
        assert Keyword.get(opts, :url) ==
                 "/v2/objects/people/records?matching_attribute=email_addresses"

        assert Keyword.get(opts, :json) == %{
                 data: %{
                   values: %{
                     email_addresses: [%{email_address: email}],
                     company: [
                       %{
                         ~c"target_object" => company_id["object_id"],
                         ~c"target_record_id" => company_id["record_id"]
                       }
                     ]
                   }
                 }
               }

        assert Keyword.get(opts, :headers) == [
                 {"content-type", "application/json"},
                 {"authorization", "Bearer #{api_key}"}
               ]

        {:ok, %{}}
      end)

      Environment |> stub(:attio_api_key, fn -> api_key end)

      # When
      assert :ok =
               Attio.process_event(
                 %{event_id: [:organization, :create], name: organization_name, email: email},
                 {process_name, table_id}
               )
    end

    test "when user_authenticate" do
      # Given
      organization_name = "tuist"
      email = "test@tuist.io"
      table_id = "table_id"
      process_name = "attio"
      company_id = %{"object_id" => "1234", "record_id" => "5678"}
      api_key = "api_key"

      Req
      |> expect(:put, fn _req, opts ->
        assert Keyword.get(opts, :url) ==
                 "/v2/objects/companies/records?matching_attribute=domains"

        assert Keyword.get(opts, :json) == %{
                 data: %{
                   values: %{
                     name: [%{value: organization_name}],
                     domains: [%{domain: "#{organization_name}.cloud.tuist.io"}]
                   }
                 }
               }

        assert Keyword.get(opts, :headers) == [
                 {"content-type", "application/json"},
                 {"authorization", "Bearer #{api_key}"}
               ]

        {:ok, %{body: %{"data" => %{"id" => company_id}}}}
      end)
      |> expect(:put, fn _req, opts ->
        assert Keyword.get(opts, :url) ==
                 "/v2/objects/people/records?matching_attribute=email_addresses"

        assert Keyword.get(opts, :json) == %{
                 data: %{
                   values: %{
                     email_addresses: [%{email_address: email}],
                     company: [
                       %{
                         ~c"target_object" => company_id["object_id"],
                         ~c"target_record_id" => company_id["record_id"]
                       }
                     ]
                   }
                 }
               }

        assert Keyword.get(opts, :headers) == [
                 {"content-type", "application/json"},
                 {"authorization", "Bearer #{api_key}"}
               ]

        {:ok, %{}}
      end)

      Environment |> stub(:attio_api_key, fn -> api_key end)

      # When
      assert :ok =
               Attio.process_event(
                 %{event_id: [:organization, :create], name: organization_name, email: email},
                 {process_name, table_id}
               )
    end
  end
end
