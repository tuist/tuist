require 'cucumber/create_meta'

describe 'createMeta' do
  it 'generates a Meta message with platform information' do
    meta = Cucumber::CreateMeta.create_meta('cucumba-ruby', 'X.Y.Z')

    expect(meta.protocol_version).to match(/\d+\.\d+\.\d+/)
    expect(meta.implementation.name).to eq('cucumba-ruby')
    expect(meta.implementation.version).to eq('X.Y.Z')
    expect(meta.runtime.name).to match(/(jruby|ruby)/)
    expect(meta.runtime.version).to eq(RUBY_VERSION)
    expect(meta.os.name).to match(/.+/)
    expect(meta.os.version).to match(/.+/)
    expect(meta.cpu.name).to match(/.+/)
  end
end
