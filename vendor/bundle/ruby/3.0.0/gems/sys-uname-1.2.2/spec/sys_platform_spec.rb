##############################################################################
# sys_platform_spec.rb
#
# Test suite for the Sys::Platform class.
##############################################################################
require 'rspec'
require 'sys/uname'
require 'rbconfig'

RSpec.describe Sys::Platform do

  before(:context) do
    @host_os = RbConfig::CONFIG['host_os']
    @windows = @host_os =~ /mingw|mswin|windows/i ? true : false
  end

  example "the VERSION constant is set to the expected value" do
    expect(Sys::Platform::VERSION).to eql('1.2.2')
    expect(Sys::Platform::VERSION).to be_frozen
  end

  example "the ARCH constant is defined" do
    expect(Sys::Platform::ARCH).to be_kind_of(Symbol)
  end

  example "the OS constant is defined" do
    expect(Sys::Platform::OS).to be_kind_of(Symbol)
  end

  example "the IMPL constant is defined" do
    expect(Sys::Platform::IMPL).to be_kind_of(Symbol)
  end

  example "the IMPL returns an expected value", :if => @windows do
    expect(Sys::Platform::IMPL).to include([:mingw, :mswin])
  end

  example "the mac? method is defined and returns a boolean" do
    expect(Sys::Platform).to respond_to(:mac?)
    expect(Sys::Platform.mac?).to eql(true).or eql(false)
  end

  example "the windows? method is defined and returns a boolean" do
    expect(Sys::Platform).to respond_to(:windows?)
    expect(Sys::Platform.windows?).to eql(true).or eql(false)
  end

  example "the windows? method returns the expected value" do
    expect(Sys::Platform.windows?).to eql(@windows)
  end

  example "the unix? method is defined and returns a boolean" do
    expect(Sys::Platform).to respond_to(:unix?)
    expect(Sys::Platform.unix?).to eql(true).or eql(false)
  end

  example "the unix? method returns the expected value" do
    expect(Sys::Platform.unix?).not_to eql(@windows)
  end

  example "the solaris? method is defined and returns a boolean" do
    expect(Sys::Platform).to respond_to(:solaris?)
    expect(Sys::Platform.solaris?).to eql(true).or eql(false)
  end

  example "the linux? method is defined and returns a boolean" do
    expect(Sys::Platform).to respond_to(:linux?)
    expect(Sys::Platform.linux?).to eql(true).or eql(false)
  end

  example "the bsd? method is defined and returns a boolean" do
    expect(Sys::Platform).to respond_to(:bsd?)
    expect(Sys::Platform.bsd?).to eql(true).or eql(false)
  end
end
