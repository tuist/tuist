defmodule Tuist.MauticTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.Mautic

  setup do
    stub(Tuist.Environment, :mautic_username, fn -> "username" end)
    stub(Tuist.Environment, :mautic_password, fn -> "password" end)
    :ok
  end

  describe "companies" do
    test "paginates all the companies" do
      # Given
      url = "#{Mautic.base_url()}/companies"
      auth = {:basic, "username:password"}
      retry = :safe_transient

      first_opts = [
        params: %{start: 0, limit: 1},
        auth: auth,
        retry: retry
      ]

      expect(Req, :get!, fn ^url, ^first_opts ->
        %{status: 200, body: %{"companies" => %{"1" => %{id: 1}}}}
      end)

      second_opts = [
        params: %{start: 1, limit: 1},
        auth: auth,
        retry: retry
      ]

      expect(Req, :get!, fn ^url, ^second_opts ->
        %{status: 200, body: %{"companies" => %{}}}
      end)

      # When
      got = Mautic.companies(page_limit: 1)

      # Then
      assert got == {:ok, %{"1" => %{id: 1}}}
    end
  end

  describe "create_company" do
    test "creates a new company" do
      # Given
      url = "#{Mautic.base_url()}/companies/new"
      company = %{name: "Test Company", email: "test@example.com"}

      expected_opts = [
        headers: %{"content-type" => ["application/json"]},
        json: company,
        auth: {:basic, "username:password"},
        retry: :safe_transient
      ]

      expect(Req, :post!, fn ^url, ^expected_opts ->
        %{status: 201, body: %{"company" => %{id: 1, name: "Test Company"}}}
      end)

      # When
      result = Mautic.create_company(company)

      # Then
      assert result == {:ok, %{"company" => %{id: 1, name: "Test Company"}}}
    end
  end

  describe "update_company" do
    test "updates an existing company" do
      # Given
      company_id = 1
      url = "#{Mautic.base_url()}/companies/#{company_id}/edit"
      company_data = %{name: "Updated Company"}

      expected_opts = [
        headers: %{"content-type" => ["application/json"]},
        json: company_data,
        auth: {:basic, "username:password"},
        retry: :safe_transient
      ]

      expect(Req, :patch!, fn ^url, ^expected_opts ->
        %{status: 200, body: %{"company" => %{id: 1, name: "Updated Company"}}}
      end)

      # When
      result = Mautic.update_company(company_id, company_data)

      # Then
      assert result == {:ok, %{"company" => %{id: 1, name: "Updated Company"}}}
    end
  end

  describe "remove_company" do
    test "removes a company" do
      # Given
      company_id = 1
      url = "#{Mautic.base_url()}/companies/#{company_id}/delete"

      expected_opts = [
        headers: %{"content-type" => ["application/json"]},
        auth: {:basic, "username:password"},
        retry: :safe_transient
      ]

      expect(Req, :delete!, fn ^url, ^expected_opts ->
        %{status: 200}
      end)

      # When
      result = Mautic.remove_company(company_id)

      # Then
      assert result == :ok
    end
  end

  describe "add_contact_to_company" do
    test "adds a contact to a company" do
      # Given
      contact_id = 1
      company_id = 2
      url = "#{Mautic.base_url()}/companies/#{company_id}/contact/#{contact_id}/add"

      expected_opts = [
        headers: %{"content-type" => ["application/json"]},
        auth: {:basic, "username:password"},
        retry: :safe_transient
      ]

      expect(Req, :post!, fn ^url, ^expected_opts ->
        %{status: 200}
      end)

      # When
      result = Mautic.add_contact_to_company(contact_id, company_id)

      # Then
      assert result == :ok
    end
  end

  describe "remove_contact_from_company" do
    test "removes a contact from a company" do
      # Given
      contact_id = 1
      company_id = 2
      url = "#{Mautic.base_url()}/companies/#{company_id}/contact/#{contact_id}/remove"

      expected_opts = [
        headers: %{"content-type" => ["application/json"]},
        auth: {:basic, "username:password"},
        retry: :safe_transient
      ]

      expect(Req, :post!, fn ^url, ^expected_opts ->
        %{status: 200}
      end)

      # When
      result = Mautic.remove_contact_from_company(contact_id, company_id)

      # Then
      assert result == :ok
    end
  end

  describe "add_contact_to_segment" do
    test "adds a contact to a segment" do
      # Given
      contact_id = 1
      segment_id = 2
      url = "#{Mautic.base_url()}/segments/#{segment_id}/contact/#{contact_id}/add"

      expected_opts = [
        headers: %{"content-type" => ["application/json"]},
        auth: {:basic, "username:password"},
        retry: :safe_transient
      ]

      expect(Req, :post!, fn ^url, ^expected_opts ->
        %{status: 200}
      end)

      # When
      result = Mautic.add_contact_to_segment(contact_id, segment_id)

      # Then
      assert result == :ok
    end
  end

  describe "contacts" do
    test "returns all contacts" do
      # Given
      url = "#{Mautic.base_url()}/contacts"

      expected_opts = [
        params: %{limit: 100, start: 0},
        auth: {:basic, "username:password"},
        retry: :safe_transient
      ]

      expect(Req, :get!, fn ^url, ^expected_opts ->
        %{status: 200, body: %{"contacts" => %{"1" => %{id: 1, email: "test@example.com"}}}}
      end)

      # When
      result = Mautic.contacts()

      # Then
      assert result == {:ok, %{"1" => %{id: 1, email: "test@example.com"}}}
    end
  end

  describe "create_contact" do
    test "creates a new contact" do
      # Given
      url = "#{Mautic.base_url()}/contacts/new"
      contact = %{email: "test@example.com", firstname: "Test"}

      expected_opts = [
        headers: %{"content-type" => ["application/json"]},
        json: contact,
        auth: {:basic, "username:password"},
        retry: :safe_transient
      ]

      expect(Req, :post!, fn ^url, ^expected_opts ->
        %{status: 201, body: %{"contact" => %{id: 1, email: "test@example.com"}}}
      end)

      # When
      result = Mautic.create_contact(contact)

      # Then
      assert result == {:ok, %{"contact" => %{id: 1, email: "test@example.com"}}}
    end
  end

  describe "update_contact" do
    test "updates an existing contact" do
      # Given
      contact_id = 1
      url = "#{Mautic.base_url()}/contacts/#{contact_id}/edit"
      contact_data = %{firstname: "Updated Name"}

      expected_opts = [
        headers: %{"content-type" => ["application/json"]},
        json: contact_data,
        auth: {:basic, "username:password"},
        retry: :safe_transient
      ]

      expect(Req, :patch!, fn ^url, ^expected_opts ->
        %{status: 200, body: %{"contact" => %{id: 1, firstname: "Updated Name"}}}
      end)

      # When
      result = Mautic.update_contact(contact_id, contact_data)

      # Then
      assert result == {:ok, %{"contact" => %{id: 1, firstname: "Updated Name"}}}
    end
  end

  describe "remove_contact" do
    test "removes a contact" do
      # Given
      contact_id = 1
      url = "#{Mautic.base_url()}/contacts/#{contact_id}/delete"

      expected_opts = [
        headers: %{"content-type" => ["application/json"]},
        auth: {:basic, "username:password"},
        retry: :safe_transient
      ]

      expect(Req, :delete!, fn ^url, ^expected_opts ->
        %{status: 200}
      end)

      # When
      result = Mautic.remove_contact(contact_id)

      # Then
      assert result == :ok
    end
  end

  describe "create_contacts" do
    test "creates multiple contacts" do
      # Given
      url = "#{Mautic.base_url()}/contacts/batch/new"

      contacts = [
        %{email: "test1@example.com", firstname: "Test1"},
        %{email: "test2@example.com", firstname: "Test2"}
      ]

      expected_opts = [
        headers: %{"content-type" => ["application/json"]},
        json: contacts,
        auth: {:basic, "username:password"},
        retry: :safe_transient
      ]

      expect(Req, :post!, fn ^url, ^expected_opts ->
        %{status: 201, body: %{"contacts" => [%{id: 1}, %{id: 2}]}}
      end)

      # When
      result = Mautic.create_contacts(contacts)

      # Then
      assert result == :ok
    end
  end

  describe "remove_contacts" do
    test "removes multiple contacts in batch" do
      # Given
      url = "#{Mautic.base_url()}/contacts/batch/delete"
      contact_ids = [1, 2, 3]

      expected_opts = [
        headers: %{"content-type" => ["application/json"]},
        json: contact_ids,
        auth: {:basic, "username:password"},
        retry: :safe_transient
      ]

      expect(Req, :delete!, fn ^url, ^expected_opts ->
        %{status: 200}
      end)

      # When
      result = Mautic.remove_contacts(contact_ids)

      # Then
      assert result == :ok
    end
  end
end
