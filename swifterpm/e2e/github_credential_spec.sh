request_credentials() {
  local protocol="$1"
  local host="$2"
  local operation="$3"
  local token="${4-e2e-test-token}"
  printf 'protocol=%s\nhost=%s\n\n' "${protocol}" "${host}" |
    SWIFTERPM_E2E_GIT_TOKEN="${token}" bash "${PWD}/e2e/github-credential-helper.sh" "${operation}"
}

fill_isolated_git_credentials() {
  printf 'protocol=https\nhost=github.com\n\n' |
    env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 \
      GIT_CONFIG_COUNT=2 GIT_CONFIG_KEY_0=credential.helper GIT_CONFIG_VALUE_0='' \
      GIT_CONFIG_KEY_1=credential.https://github.com.helper \
      GIT_CONFIG_VALUE_1="!bash \"${PWD}/e2e/github-credential-helper.sh\"" \
      SWIFTERPM_E2E_GIT_TOKEN=e2e-test-token GIT_TERMINAL_PROMPT=0 \
      git credential fill
}

Describe 'swifterpm E2E Git credentials'
  It 'provides the explicit job credential for HTTPS GitHub requests'
    When call request_credentials https github.com get
    The status should be success
    The output should include 'username=x-access-token'
    The output should include 'password=e2e-test-token'
  End

  It 'does not provide credentials to other hosts'
    When call request_credentials https gitlab.com get
    The status should be success
    The output should be blank
  End

  It 'does not provide credentials to a GitHub-looking host'
    When call request_credentials https github.com.example.com get
    The status should be success
    The output should be blank
  End

  It 'does not provide credentials over HTTP'
    When call request_credentials http github.com get
    The status should be success
    The output should be blank
  End

  It 'does not require credentials for local anonymous runs'
    When call request_credentials https github.com get ''
    The status should be success
    The output should be blank
  End

  It 'does not store credentials'
    When call request_credentials https github.com store
    The status should be success
    The output should be blank
  End

  It 'provides credentials through Git despite isolated global and system config'
    When call fill_isolated_git_credentials
    The status should be success
    The output should include 'username=x-access-token'
    The output should include 'password=e2e-test-token'
  End
End
