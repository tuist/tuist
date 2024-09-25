defmodule Tuist.AWS.CredentialsTest do
  use ExUnit.Case, async: false
  use Mimic
  alias Tuist.AWS.Credentials
  alias Tuist.Environment

  setup :set_mimic_from_context

  describe "get_token_file_credentials/1" do
    @tag :tmp_dir
    test "returns the right values when a token file is present", %{tmp_dir: tmp_dir} do
      # Given
      Environment |> stub(:s3_endpoint, fn -> "https://s3.amazonaws.com" end)
      Environment |> stub(:s3_access_key_id, fn -> "s3_access_key_id" end)
      Environment |> stub(:s3_secret_access_key, fn -> "s3_secret_access_key" end)
      Environment |> stub(:aws_region, fn -> "auto" end)
      Environment |> stub(:aws_use_session_token?, fn -> true end)
      Environment |> stub(:aws_session_token, fn -> "session_token" end)
      Environment |> stub(:aws_role_arn, fn -> "role_arn" end)
      Environment |> stub(:aws_role_session_name, fn _ -> "role_session_name" end)

      token = UUIDv7.generate()
      token_path = Path.join(tmp_dir, "token")
      File.write!(token_path, token)
      Environment |> stub(:aws_web_identity_token_file, fn -> token_path end)
      ttl = :timer.minutes(10)
      cache = UUIDv7.generate() |> String.to_atom()
      {:ok, _} = Cachex.start_link(name: cache)

      duration_seconds = trunc(ttl / 1000)

      Req
      |> stub(:get!, fn "https://sts.amazonaws.com/",
                        form: %{
                          "Action" => "AssumeRoleWithWebIdentity",
                          "RoleArn" => "role_arn",
                          "RoleSessionName" => "role_session_name",
                          "WebIdentityToken" => ^token,
                          "Version" => "2006-03-01",
                          "DurationSeconds" => ^duration_seconds
                        },
                        headers: [{"Content-Type", "application/x-www-form-urlencoded"}] ->
        %{
          body: """
          <AssumeRoleWithWebIdentityResponse xmlns="https://sts.amazonaws.com/doc/2006-03-01/">
            <AssumeRoleWithWebIdentityResult>
              <Credentials>
                <AccessKeyId>ASIAEXAMPLE12345</AccessKeyId>
                <SecretAccessKey>wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY</SecretAccessKey>
                <SessionToken>FQoGZXIvYXdzEEkaD...EXAMPLETOKEN</SessionToken>
                <Expiration>2024-09-25T12:34:56Z</Expiration>
              </Credentials>
              <SubjectFromWebIdentityToken>example-user-id</SubjectFromWebIdentityToken>
              <AssumedRoleUser>
                <AssumedRoleId>AROAAEXAMPLEID:session-name</AssumedRoleId>
                <Arn>arn:aws:sts::123456789012:assumed-role/example-role/session-name</Arn>
              </AssumedRoleUser>
              <PackedPolicySize>6</PackedPolicySize>
            </AssumeRoleWithWebIdentityResult>
            <ResponseMetadata>
              <RequestId>a123b456-c789-012d-345e-6789fgh012ij</RequestId>
            </ResponseMetadata>
          </AssumeRoleWithWebIdentityResponse>
          """
        }
      end)

      # When
      got = Credentials.get_token_file_credentials(cache: cache, ttl: ttl)

      # Then
      assert got == %{
               session_token: ~c"FQoGZXIvYXdzEEkaD...EXAMPLETOKEN",
               access_key_id: ~c"ASIAEXAMPLE12345",
               secret_access_key: ~c"wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
             }
    end
  end
end
