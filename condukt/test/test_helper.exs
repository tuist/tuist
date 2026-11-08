Mimic.copy(MuonTrap)
Mimic.copy(ReqLLM)

Code.require_file("support/llm_provider.ex", __DIR__)

# Virtual sandbox tests are tagged `:virtual_sandbox` and excluded by
# default. They rely on the bashkit NIF and run reliably locally, but on
# Linux CI runners merely loading the NIF in the same BEAM process as the
# rest of the suite has reproduced intermittent segfaults during BEAM
# teardown. Until that is root-caused, opt in explicitly:
#
#   mix test --include virtual_sandbox
#
# Or run only the Virtual sandbox suite:
#
#   mix test --only virtual_sandbox
#
# Microsandbox live tests are tagged `:microsandbox_sandbox` and excluded by
# default. They boot a real microVM and rely on supported local hardware
# virtualization, so keep them opt-in:
#
#   mix test --only microsandbox_sandbox
#
ExUnit.start(exclude: [virtual_sandbox: true, k8s_sandbox: true, microsandbox_sandbox: true])
