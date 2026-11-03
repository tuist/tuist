# Generate reviewable OpenBao configuration from non-secret inputs. No API calls.
require 'json'

module KuraOpenBaoConfig
  AUDIENCE = 'openbao.kura.tuist.dev'.freeze

  def self.plan(env)
    namespace = env.fetch('KURA_OPENBAO_SERVER_NAMESPACE')
    role = env.fetch('KURA_OPENBAO_ROLE')
    key = env.fetch('KURA_OPENBAO_KEY_NAME')
    transit = env.fetch('KURA_OPENBAO_TRANSIT_MOUNT', 'transit')
    auth = env.fetch('KURA_OPENBAO_AUTH_MOUNT', 'kubernetes')
    old_keys = env.fetch('KURA_OPENBAO_DECRYPT_KEY_NAMES', '').split(',').map(&:strip)
    names = [namespace, role, key, transit, auth] + old_keys
    raise 'invalid name: use a single alphanumeric/hyphen/underscore path segment' unless names.all? { |name| name.match?(/\A[a-zA-Z0-9][a-zA-Z0-9_-]*\z/) }
    policy = "path \"#{transit}/encrypt/#{key}\" { capabilities = [\"update\"] }\n"
    ([key] + old_keys).uniq.each do |name|
      policy += "path \"#{transit}/decrypt/#{name}\" { capabilities = [\"update\"] }\n"
    end
    {
      transit_mount: transit,
      auth_mount: auth,
      key_name: key,
      key_configuration: {
        type: 'aes256-gcm96', derived: true, convergent_encryption: false,
        exportable: false, allow_plaintext_backup: false, auto_rotate_period: '2160h'
      },
      policy_name: role,
      policy: policy,
      role_name: role,
      role: {
        bound_service_account_names: ['tuist-server'],
        bound_service_account_namespaces: [namespace], audience: AUDIENCE,
        token_policies: [role], token_ttl: '5m', token_max_ttl: '5m',
        token_type: 'batch', token_no_default_policy: true
      }
    }
  end
end

puts JSON.pretty_generate(KuraOpenBaoConfig.plan(ENV)) if $PROGRAM_NAME == __FILE__
