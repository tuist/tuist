defmodule Atlas.MCP.Tools.SendAccountEmailTest do
  use Atlas.MCP.ToolCase
  use Oban.Testing, repo: Atlas.Repo

  alias Atlas.GTM.DirectEmails
  alias Atlas.GTM.Workers.DeliverDirectEmail
  alias Atlas.MCP.Tools.SendAccountEmail

  @body "Your usage-based pricing starts on 22 October 2026."

  test "queues an email to an explicit address" do
    user = insert_user!()

    assert {:ok, %{delivery: delivery, duplicate: false}} =
             execute_tool(SendAccountEmail, conn_for(user), %{
               "email" => "recipient@example.com",
               "recipient_name" => "Riley",
               "subject" => "Your Tuist pricing is changing",
               "body_markdown" => @body
             })

    assert delivery.kind == "direct"
    assert delivery.recipient_email == "recipient@example.com"
    assert delivery.recipient_name == "Riley"
    assert delivery.status == "pending"
    refute delivery.account_id

    assert DirectEmails.get_delivery(delivery.id).metadata["body_markdown"] == @body
    assert_enqueued(worker: DeliverDirectEmail, args: %{"delivery_id" => delivery.id})
  end

  test "addresses the account's billing contact" do
    account = insert_account!(%{billing: %{email: "billing@acme.example"}})

    assert {:ok, %{delivery: delivery}} =
             execute_tool(SendAccountEmail, executive_mcp_conn(), %{
               "account_key" => account.account_key,
               "subject" => "Your Tuist pricing is changing",
               "body_markdown" => @body
             })

    assert delivery.recipient_email == "billing@acme.example"
    assert delivery.account_id == account.id
    assert delivery.account_key == account.account_key
  end

  test "resolves the account by handle" do
    account = insert_account!(%{billing: %{email: "billing@acme.example"}})
    handle = insert_handle!(account)

    assert {:ok, %{delivery: delivery}} =
             execute_tool(SendAccountEmail, executive_mcp_conn(), %{
               "handle" => handle.handle,
               "subject" => "A notice",
               "body_markdown" => @body
             })

    assert delivery.recipient_email == "billing@acme.example"
    assert delivery.account_id == account.id
  end

  test "attributes an explicit address to the account when both are given" do
    account = insert_account!(%{billing: %{email: "billing@acme.example"}})

    assert {:ok, %{delivery: delivery}} =
             execute_tool(SendAccountEmail, executive_mcp_conn(), %{
               "account_key" => account.account_key,
               "email" => "cto@acme.example",
               "subject" => "A notice",
               "body_markdown" => @body
             })

    assert delivery.recipient_email == "cto@acme.example"
    assert delivery.account_id == account.id
  end

  test "asks for an address when the account has no billing contact" do
    account = insert_account!()

    assert {:error, message} =
             execute_tool(SendAccountEmail, executive_mcp_conn(), %{
               "account_key" => account.account_key,
               "subject" => "A notice",
               "body_markdown" => @body
             })

    assert message =~ "has no billing email"
  end

  test "reports an unknown account" do
    assert {:error, message} =
             execute_tool(SendAccountEmail, executive_mcp_conn(), %{
               "account_key" => "missing-co",
               "subject" => "A notice",
               "body_markdown" => @body
             })

    assert message =~ "Account not found"
  end

  test "requires a recipient" do
    assert {:error, message} =
             execute_tool(SendAccountEmail, executive_mcp_conn(), %{
               "subject" => "A notice",
               "body_markdown" => @body
             })

    assert message =~ "Provide email"
  end

  test "reports a malformed argument" do
    assert {:error, message} =
             execute_tool(SendAccountEmail, executive_mcp_conn(), %{
               "email" => "not-an-address",
               "subject" => "A notice",
               "body_markdown" => @body
             })

    assert message =~ "recipient_email is not a valid email address"
  end

  test "reports a repeated call as a duplicate rather than sending twice" do
    args = %{
      "email" => "recipient@example.com",
      "subject" => "Your Tuist pricing is changing",
      "body_markdown" => @body
    }

    conn = executive_mcp_conn()

    assert {:ok, %{delivery: first, duplicate: false}} = execute_tool(SendAccountEmail, conn, args)
    assert {:ok, %{delivery: second, duplicate: true}} = execute_tool(SendAccountEmail, conn, args)

    assert second.id == first.id
  end
end
