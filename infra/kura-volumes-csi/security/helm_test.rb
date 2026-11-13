require 'yaml'
require 'tmpdir'
require 'fileutils'
require 'open3'
root=File.expand_path('../../helm/tuist', __dir__)
rack_nodes=File.expand_path('../../helm/rack-nodes', __dir__)
# The node plugins render from the unwaited rack-nodes release over the same values.
plugin=lambda do |*extra|
  out,err,status=Open3.capture3('helm','template','tuist-rack-nodes',rack_nodes,'-f',"#{root}/values.yaml",'--set','kuraFleet.enabled=true','--set','kuraVolumesCSI.enabled=true','--set','kuraVolumesCSI.image.tag=test',*extra)
  raise err unless status.success?
  raise 'static key-service token still projected' if out.include?('audience: kura-volume-keys.tuist.dev')
  YAML.load_stream(out).compact.find { |d| d['kind']=='DaemonSet' && d.dig('metadata','name')=='kura-volumes-csi-node' }.dig('spec','template','spec','containers',0)
end
Dir.mktmpdir('kura-security-chart') do |chart|
  FileUtils.mkdir_p("#{chart}/templates")
  File.write("#{chart}/Chart.yaml", "apiVersion: v2\nname: tuist\nversion: 0.1.0\n")
  %w(values.yaml templates/_helpers.tpl templates/kura-volumes-csi.yaml templates/kura-volumes-csi-admission.yaml templates/server-deployment.yaml templates/server-config-external-secrets.yaml).each { |p| FileUtils.cp("#{root}/#{p}", "#{chart}/#{p}") }
  args=['helm','template','tuist',chart,'--set','server.license.key=render-test-only','--set','server.config.managedSecrets=true','--set','server.hosted=true','--set','server.image.tag=test','--set','kuraFleet.enabled=true','--set','kuraVolumesCSI.enabled=true','--set','kuraVolumesCSI.image.tag=test','--set','server.managedSecrets=true']
  out,err,status=Open3.capture3(*args); raise err unless status.success?
  docs=YAML.load_stream(out).compact
  raise 'root keys synced by default' if out.include?('KURA_VOLUME_ROOT_KEYS/value')
  raise 'missing fail-closed policies' unless docs.count { |d| d['kind']=='ValidatingAdmissionPolicy' && d.dig('spec','failurePolicy')=='Fail' } == 5
  claim_node=docs.find { |d| d['kind']=='ValidatingAdmissionPolicyBinding' && d.dig('metadata','name')=='kura-csi-pv-claim-node' }
  raise 'claim-node policy not bound to Kura claims' unless claim_node.dig('spec','paramRef') == {'namespace'=>'kura','selector'=>{'matchLabels'=>{'app.kubernetes.io/managed-by'=>'kura-controller'}},'parameterNotFoundAction'=>'Deny'}
  cluster_role=docs.find { |d| d['kind']=='ClusterRole' && d.dig('metadata','name')=='kura-volumes-csi-node' }
  raise 'cluster-wide PVC writes' if cluster_role['rules'].any? { |r| r['resources'].include?('persistentvolumeclaims') && (r['verbs'] & %w(update patch create delete)).any? }
  raise 'CSI Secret access' if cluster_role['rules'].any? { |r| (r['resources'] & %w(secrets *)).any? }
  namespaced=docs.find { |d| d['kind']=='Role' && d.dig('metadata','name')=='kura-volumes-csi-claims' }
  raise 'claim role not scoped to kura' unless namespaced.dig('metadata','namespace')=='kura'
  tokens=docs.find { |d| d['kind']=='Role' && d.dig('metadata','name')=='kura-volumes-csi-key-tokens' }
  raise 'token minting not limited to the plugin identity' unless tokens['rules']==[{'apiGroups'=>[''],'resources'=>['serviceaccounts/token'],'resourceNames'=>['kura-volumes-csi-node'],'verbs'=>['create']}]
  raise 'cluster-wide token minting' if cluster_role['rules'].any? { |r| r['resources'].include?('serviceaccounts/token') }
  raise 'node plugin in the waited release' if docs.any? { |d| d['kind']=='DaemonSet' }
  driver=plugin.call
  raise 'static key-service token still projected' if out.include?('audience: kura-volume-keys.tuist.dev')
  raise 'pod identity missing' unless (%w(POD_NAMESPACE POD_NAME POD_UID SERVICE_ACCOUNT_NAME) - driver['env'].map { |e| e['name'] }).empty?
  raise 'unpinned key rendered' if driver['env'].any? { |e| e['name']=='KEY_SERVICE_PUBLIC_KEY' }
  raise 'transport keys synced by default' if out.include?('KURA_VOLUME_TRANSPORT_KEYS/value')
  out,err,status=Open3.capture3(*args,'--set','kuraVolumesCSI.keyServicePublicKey=cGlubmVk','--set','server.config.kuraVolumeTransportKeys.enabled=true')
  raise err unless status.success?
  driver=plugin.call('--set','kuraVolumesCSI.keyServicePublicKey=cGlubmVk')
  raise 'pinned key not passed' unless driver['env'].include?({'name'=>'KEY_SERVICE_PUBLIC_KEY','value'=>'cGlubmVk'})
  raise 'transport keys not synced' unless out.include?('KURA_VOLUME_TRANSPORT_KEYS/value')
  out,err,status=Open3.capture3(*args,'--set','server.config.kuraVolumeRootKeys.enabled=true')
  raise err unless status.success?
  raise 'root keys not synced' unless out.include?('KURA_VOLUME_ROOT_KEYS/value')
  raise 'stale external key-service configuration' if out.include?('KURA_VOLUME_KMS_') || out.include?('sts.amazonaws.com')
  puts 'PASS: root and transport key sync, CSI admission, key-bound token minting and namespaced RBAC'

end
