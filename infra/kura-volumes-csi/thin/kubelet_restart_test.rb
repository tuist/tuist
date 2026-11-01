require 'json'
require 'yaml'
require 'open3'

# Qualifies capacity withdrawal against kubelet re-admission: a resident pod
# requesting tuist.dev/kura-disk must survive a kubelet restart after the CSI
# plugin removed the resource, while a published zero is enforced. ONLY for the
# disposable kind-kura-kubelet-restart cluster; it restarts that node's kubelet.
CFG = ENV.fetch('KURA_KUBELET_KUBECONFIG')
raise 'Use only the disposable kind-kura-kubelet-restart cluster' unless YAML.load_file(CFG)['current-context'] == 'kind-kura-kubelet-restart'
NODE = 'kura-kubelet-restart-control-plane'
RESOURCE = 'tuist.dev/kura-disk'

def kube(*args, input: nil)
  out, err, status = Open3.capture3('kubectl', '--kubeconfig', CFG, *args, stdin_data: input.to_s)
  raise "kubectl #{args.join(' ')}: #{err}" unless status.success?
  out
end

def advertise(value)
  kube('patch', 'node', NODE, '--subresource=status', '--type=merge', '-p', JSON.generate({ 'status' => { 'capacity' => { RESOURCE => value } } }))
end

def pod(name)
  JSON.parse(kube('get', 'pod', name, '-o', 'json'))
end

def wait_for(description, timeout: 120)
  deadline = Time.now + timeout
  until (result = yield)
    raise "timed out waiting for #{description}" if Time.now > deadline
    sleep 2
  end
  result
end

def restart_kubelet
  _, err, status = Open3.capture3('docker', 'exec', NODE, 'systemctl', 'restart', 'kubelet')
  raise err unless status.success?
  sleep 5
  wait_for('node Ready') do
    node = JSON.parse(kube('get', 'node', NODE, '-o', 'json'))
    node.dig('status', 'conditions').any? { |c| c['type'] == 'Ready' && c['status'] == 'True' }
  end
end

def run_resident(name)
  kube('apply', '-f', '-', input: JSON.generate({
    'apiVersion' => 'v1', 'kind' => 'Pod', 'metadata' => { 'name' => name, 'namespace' => 'default' },
    'spec' => { 'containers' => [{ 'name' => 'pause', 'image' => 'registry.k8s.io/pause:3.10',
                                   'resources' => { 'requests' => { RESOURCE => '1Gi' }, 'limits' => { RESOURCE => '1Gi' } } }] }
  }))
  wait_for("#{name} Running") { pod(name).dig('status', 'phase') == 'Running' }
  pod(name).dig('metadata', 'uid')
end

# After a kubelet restart the pod either keeps running with no restarts, or
# kubelet re-admission rejects it and stops its containers.
def outcome_after_restart(name, uid)
  restart_kubelet
  sleep 20
  current = pod(name)
  raise "#{name} was replaced" unless current.dig('metadata', 'uid') == uid
  phase = current.dig('status', 'phase')
  restarts = current.dig('status', 'containerStatuses', 0, 'restartCount')
  { phase: phase, reason: current.dig('status', 'reason'), message: current.dig('status', 'message'), restarts: restarts }
end

results = []
begin
  advertise('10Gi')
  wait_for('advertised capacity') { JSON.parse(kube('get', 'node', NODE, '-o', 'json')).dig('status', 'allocatable', RESOURCE) }
  uid = run_resident('withdrawn')
  advertise(nil)
  withdrawn = outcome_after_restart('withdrawn', uid)
  raise "withdrawn resource disrupted the resident pod: #{withdrawn}" unless withdrawn[:phase] == 'Running' && withdrawn[:restarts] == 0
  results << { name: 'resident pod after withdrawal and kubelet restart', result: withdrawn }

  advertise('10Gi')
  wait_for('re-advertised capacity') { JSON.parse(kube('get', 'node', NODE, '-o', 'json')).dig('status', 'allocatable', RESOURCE) }
  uid = run_resident('zeroed')
  advertise('0')
  zeroed = outcome_after_restart('zeroed', uid)
  raise "a present zero was not enforced: #{zeroed}" if zeroed[:phase] == 'Running'
  rejected = JSON.parse(kube('get', 'events', '--field-selector', "involvedObject.uid=#{uid}", '-o', 'json'))['items'].map { |e| e['reason'] }
  raise "kubelet did not reject the pod on re-admission: #{rejected}" unless rejected.include?("OutOf#{RESOURCE}")
  zeroed[:admission] = "OutOf#{RESOURCE}"
  results << { name: 'resident pod after publishing zero and kubelet restart', result: zeroed }
  puts JSON.pretty_generate(results)
ensure
  kube('delete', 'pod', 'withdrawn', 'zeroed', '--ignore-not-found', '--wait=false')
end
