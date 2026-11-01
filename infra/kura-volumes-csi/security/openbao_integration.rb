# Disposable local API integration. Never uses a hosted context or existing Bao.
# Requires Docker, kind, kubectl, openssl and the server's installed Mix toolchain.
require 'json'
require 'net/http'
require 'openssl'
require 'open3'
require 'tmpdir'
require 'securerandom'
require_relative 'openbao-config'
$stdout.sync = true

CLUSTER = 'kura-openbao-security'.freeze
CONTEXT = "kind-#{CLUSTER}".freeze
NAMESPACE = 'tuist-openbao-test'.freeze
IMAGE = 'ghcr.io/openbao/openbao:2.7.1'.freeze
ROOT = File.expand_path('../../..', __dir__)

# Never print captured output: local fixture credentials may be in it.
def command(*args, input: nil, env: {}, chdir: ROOT)
  out, err, status = Open3.capture3(env, *args, stdin_data: input, chdir: chdir)
  unless status.success?
    # Only reveal our fixed assertions, never arbitrary tool output.
    assertions = ['real Transit encrypt failed', 'real Transit round trip failed', 'saved share did not recover',
                  'context substitution accepted', 'rotation lost the old version', 'post-rotation encrypt failed',
                  'new encryption did not use rotated key', 'rotated envelope changed the share', 'unauthorized or sealed access accepted']
    failure = assertions.find { |message| err.include?(message) }
    raise(failure || "command failed: #{args.first(2).join(' ')}")
  end
  out
end

def resource(kind, name, spec = {})
  {'apiVersion' => 'v1', 'kind' => kind, 'metadata' => {'name' => name, 'namespace' => NAMESPACE}}.merge(spec)
end

Dir.mktmpdir('kura-openbao-test') do |dir|
  kubeconfig = "#{dir}/kubeconfig"
  kubectl = ['kubectl', '--kubeconfig', kubeconfig, '--context', CONTEXT]
  created = false
  forward = nil
  begin
    clusters = command('mise', 'exec', 'kind@0.31.0', '--', 'kind', 'get', 'clusters').lines.map(&:strip)
    raise 'refusing to reuse an existing test cluster' if clusters.include?(CLUSTER)
    command('docker', 'pull', IMAGE)
    command('mise', 'exec', 'kind@0.31.0', '--', 'kind', 'create', 'cluster', '--name', CLUSTER,
            '--image', 'kindest/node:v1.34.0', '--kubeconfig', kubeconfig, '--wait', '90s')
    created = true
    puts 'Created isolated kind cluster'
    command('mise', 'exec', 'kind@0.31.0', '--', 'kind', 'load', 'docker-image', IMAGE, '--name', CLUSTER)
    command('openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '1',
            '-keyout', "#{dir}/ca.key", '-out', "#{dir}/ca.crt", '-subj', '/CN=Kura local test CA',
            '-addext', 'basicConstraints=critical,CA:TRUE', '-addext', 'keyUsage=critical,keyCertSign,cRLSign')
    File.chmod(0600, "#{dir}/ca.key")
    command('openssl', 'req', '-new', '-newkey', 'rsa:2048', '-nodes',
            '-keyout', "#{dir}/tls.key", '-out', "#{dir}/tls.csr", '-subj', '/CN=localhost')
    File.write("#{dir}/tls.ext", "basicConstraints=critical,CA:FALSE\nkeyUsage=critical,digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth\nsubjectAltName=DNS:localhost,DNS:openbao,IP:127.0.0.1\n")
    command('openssl', 'x509', '-req', '-in', "#{dir}/tls.csr", '-CA', "#{dir}/ca.crt",
            '-CAkey', "#{dir}/ca.key", '-CAcreateserial', '-days', '1', '-out', "#{dir}/tls.crt", '-extfile', "#{dir}/tls.ext")
    File.chmod(0600, "#{dir}/tls.key")
    config = <<~HCL
      ui = false
      api_addr = "https://localhost:8200"
      cluster_addr = "https://127.0.0.1:8201"
      storage "raft" {
        path = "/openbao/data"
        node_id = "local-test"
      }
      audit "file" "local" {
        options {
          file_path = "/openbao/data/audit.json"
          log_raw = "false"
        }
      }
      listener "tcp" {
        address = "0.0.0.0:8200"
        tls_cert_file = "/openbao/tls/tls.crt"
        tls_key_file = "/openbao/tls/tls.key"
      }
    HCL
    docs = [
      {'apiVersion' => 'v1', 'kind' => 'Namespace', 'metadata' => {'name' => NAMESPACE}},
      resource('ServiceAccount', 'openbao'), resource('ServiceAccount', 'tuist-server'), resource('ServiceAccount', 'unauthorized'),
      resource('Secret', 'openbao-tls', 'type' => 'Opaque', 'stringData' => {'tls.crt' => File.read("#{dir}/tls.crt"), 'tls.key' => File.read("#{dir}/tls.key")}),
      resource('ConfigMap', 'openbao-config', 'data' => {'config.hcl' => config}),
      {'apiVersion' => 'rbac.authorization.k8s.io/v1', 'kind' => 'ClusterRoleBinding', 'metadata' => {'name' => 'openbao-reviewer'},
       'roleRef' => {'apiGroup' => 'rbac.authorization.k8s.io', 'kind' => 'ClusterRole', 'name' => 'system:auth-delegator'},
       'subjects' => [{'kind' => 'ServiceAccount', 'name' => 'openbao', 'namespace' => NAMESPACE}]},
      resource('Pod', 'openbao', 'spec' => {
        'serviceAccountName' => 'openbao',
        'containers' => [{'name' => 'openbao', 'image' => IMAGE, 'args' => ['server', '-config=/openbao/config/config.hcl'],
                          'env' => [{'name' => 'SKIP_CHOWN', 'value' => 'true'}, {'name' => 'SKIP_SETCAP', 'value' => 'true'}],
                          'volumeMounts' => [{'name' => 'data', 'mountPath' => '/openbao/data'}, {'name' => 'tls', 'mountPath' => '/openbao/tls'}, {'name' => 'config', 'mountPath' => '/openbao/config'}]}],
        'volumes' => [{'name' => 'data', 'emptyDir' => {}}, {'name' => 'tls', 'secret' => {'secretName' => 'openbao-tls'}}, {'name' => 'config', 'configMap' => {'name' => 'openbao-config'}}]
      }),
      *%w(tuist-server unauthorized).map do |sa|
        resource('Pod', sa, 'spec' => {'serviceAccountName' => sa, 'containers' => [{'name' => 'pause', 'image' => 'registry.k8s.io/pause:3.10'}]})
      end
    ]
    command(*kubectl, 'apply', '-f', '-', input: JSON.generate({'apiVersion' => 'v1', 'kind' => 'List', 'items' => docs}))
    command(*kubectl, 'wait', '--for=condition=Ready', 'pod', '--all', '-n', NAMESPACE, '--timeout=90s')
    forward = Process.spawn(*kubectl, '-n', NAMESPACE, 'port-forward', 'pod/openbao', '18820:8200', out: File::NULL, err: File::NULL)
    root_token = nil
    request = lambda do |method, path, data = nil, token = root_token, expected = [200, 204]|
      uri = URI("https://localhost:18820/v1/#{path}")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.ca_file = "#{dir}/ca.crt"
      http.verify_mode = OpenSSL::SSL::VERIFY_PEER
      http.open_timeout = 3
      http.read_timeout = 10
      req = Net::HTTP.const_get(method.capitalize).new(uri)
      req['X-Vault-Token'] = token if token
      req['Content-Type'] = 'application/json'
      req.body = data.is_a?(String) ? data : JSON.generate(data) unless data.nil?
      response = http.request(req)
      raise "unexpected status #{response.code} for #{path}" unless expected.include?(response.code.to_i)
      response.body
    end
    ready = false
    30.times do
      begin
        request.call('get', 'sys/seal-status', nil, nil)
        ready = true
        break
      rescue Errno::ECONNREFUSED, EOFError, OpenSSL::SSL::SSLError
        sleep 1
      end
    end
    raise 'local OpenBao did not start' unless ready
    init = JSON.parse(request.call('put', 'sys/init', {'secret_shares' => 1, 'secret_threshold' => 1}))
    root_token = init.fetch('root_token')
    unseal_key = init.fetch('keys_base64').first
    request.call('put', 'sys/unseal', {'key' => unseal_key})
    plan = KuraOpenBaoConfig.plan('KURA_OPENBAO_SERVER_NAMESPACE' => NAMESPACE, 'KURA_OPENBAO_ROLE' => 'kura-test', 'KURA_OPENBAO_KEY_NAME' => 'kura-volume-root')
    request.call('post', 'sys/mounts/transit', {'type' => 'transit'})
    request.call('post', 'transit/keys/kura-volume-root', plan[:key_configuration])
    request.call('put', 'sys/policies/acl/kura-test', {'policy' => plan[:policy]})
    request.call('post', 'sys/auth/kubernetes', {'type' => 'kubernetes'})
    request.call('post', 'auth/kubernetes/config', {'kubernetes_host' => 'https://kubernetes.default.svc'})
    request.call('post', 'auth/kubernetes/role/kura-test', plan[:role])
    token_for = lambda do |sa, audience|
      uid = JSON.parse(command(*kubectl, '-n', NAMESPACE, 'get', 'pod', sa, '-o', 'json')).dig('metadata', 'uid')
      command(*kubectl, '-n', NAMESPACE, 'create', 'token', sa, "--audience=#{audience}",
              '--duration=10m', '--bound-object-kind=Pod', "--bound-object-name=#{sa}", "--bound-object-uid=#{uid}").strip
    end
    token_path = "#{dir}/workload-token"
    write_token = lambda { |token| File.open(token_path, 'w', 0600) { |f| f.write(token) } }
    jwt = token_for.call('tuist-server', KuraOpenBaoConfig::AUDIENCE)
    write_token.call(jwt)
    env = {'MIX_ENV' => 'test', 'TUIST_KURA_VOLUME_OPENBAO_ADDRESS' => 'https://localhost:18820',
           'TUIST_KURA_VOLUME_OPENBAO_KEY_NAME' => 'kura-volume-root', 'TUIST_KURA_VOLUME_OPENBAO_ROLE' => 'kura-test',
           'TUIST_KURA_VOLUME_OPENBAO_CA_CERT_FILE' => "#{dir}/ca.crt", 'TUIST_KURA_VOLUME_OPENBAO_TOKEN_FILE' => token_path}
    check = lambda do |mode|
      build_flags = mode == 'seed' ? [] : ['--no-compile']
      command('mise', 'exec', '--', 'mix', 'run', '--no-start', *build_flags, '../infra/kura-volumes-csi/security/openbao_check.exs', mode, "#{dir}/share",
              env: env, chdir: "#{ROOT}/server")
      puts "PASS: production provider #{mode}"
    end
    workload = JSON.parse(request.call('post', 'auth/kubernetes/login', {'role' => 'kura-test', 'jwt' => jwt}, nil)).dig('auth', 'client_token')
    puts 'PASS: real Kubernetes TokenReview login'
    fixture_context = ['fixture'].pack('m0')
    request.call('post', 'transit/encrypt/kura-volume-root', {'plaintext' => [SecureRandom.random_bytes(32)].pack('m0'),
                  'context' => fixture_context, 'associated_data' => fixture_context}, workload)
    puts 'PASS: generated Transit key and workload policy'
    check.call('seed')
    check.call('verify')
    %w(transit/keys/kura-volume-root/rotate transit/keys/kura-volume-root/config transit/encrypt/unapproved).each do |path|
      request.call('post', path, {}, workload, [403])
    end
    %w(transit/export/encryption-key/kura-volume-root transit/backup/kura-volume-root sys/storage/raft/snapshot).each do |path|
      request.call('get', path, nil, workload, [403])
    end
    puts 'PASS: workload cannot rotate, reconfigure, export, back up, or use another key'
    snapshot = request.call('get', 'sys/storage/raft/snapshot')
    request.call('post', 'transit/keys/kura-volume-root/rotate', {})
    check.call('rotated')
    write_token.call(token_for.call('unauthorized', KuraOpenBaoConfig::AUDIENCE))
    check.call('denied')
    write_token.call(token_for.call('tuist-server', 'wrong-audience'))
    check.call('denied')
    write_token.call(token_for.call('tuist-server', KuraOpenBaoConfig::AUDIENCE))
    check.call('verify')
    request.call('put', 'sys/seal', {})
    check.call('denied')
    request.call('put', 'sys/unseal', {'key' => unseal_key})
    check.call('verify')
    request.call('post', 'sys/storage/raft/snapshot-force', snapshot)
    sleep 3
    request.call('put', 'sys/unseal', {'key' => unseal_key})
    restored = JSON.parse(request.call('get', 'transit/keys/kura-volume-root'))
    raise 'snapshot did not restore the pre-rotation key state' unless restored.dig('data', 'latest_version') == 1
    check.call('verify')
    puts 'PASS: rotation, identity rejection, sealing/recovery and encrypted Raft snapshot restore'
    audit = command(*kubectl, '-n', NAMESPACE, 'exec', 'openbao', '--', 'cat', '/openbao/data/audit.json')
    records = audit.lines.map { |line| JSON.parse(line) }
    sensitive_fields = [
      records.map { |row| row.dig('request', 'data', 'jwt') }.compact,
      records.map { |row| row.dig('request', 'data', 'plaintext') }.compact,
      records.map { |row| row.dig('response', 'data', 'plaintext') }.compact
    ]
    raise 'audit did not protect identity/share fields' unless sensitive_fields.all? { |fields| !fields.empty? && fields.all? { |value| value.start_with?('hmac-sha256:') } }
    puts 'PASS: audit records protect JWTs and plaintext shares with HMAC'
  ensure
    Process.kill('TERM', forward) if forward && Process.waitpid(forward, Process::WNOHANG).nil?
    Process.waitpid(forward) rescue nil
    command('mise', 'exec', 'kind@0.31.0', '--', 'kind', 'delete', 'cluster', '--name', CLUSTER) if created
  end
end
