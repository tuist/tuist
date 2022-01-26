$LOAD_PATH << ::File.expand_path('../', __FILE__)
$LOAD_PATH << ::File.expand_path('../spec', __FILE__)

require 'fileutils'
require 'rubygems'
require 'rubygems/package_task'
require 'bundler/gem_tasks'
require 'benchmark/tasks'

require 'rspec/core/rake_task'
require 'rubocop/rake_task'

RSpec::Core::RakeTask.new(:spec)
RuboCop::RakeTask.new

task :default => ['compile:spec', 'compile:rpc', :spec, :rubocop]

desc 'Run specs'
namespace :compile do

  desc 'Compile spec protos in spec/supprt/ directory'
  task :spec do
    proto_path = ::File.expand_path('../spec/support/', __FILE__)
    proto_files = Dir[File.join(proto_path, '**', '*.proto')]
    cmd = %(protoc --plugin=./bin/protoc-gen-ruby --ruby_out=#{proto_path} -I #{proto_path} #{proto_files.join(' ')})

    puts cmd
    system(cmd)
  end

  desc 'Compile rpc protos in protos/ directory'
  task :rpc do
    proto_path = ::File.expand_path('../proto', __FILE__)
    proto_files = Dir[File.join(proto_path, '**', '*.proto')]
    output_dir = ::File.expand_path('../tmp/rpc', __FILE__)
    ::FileUtils.mkdir_p(output_dir)

    cmd = %(protoc --plugin=./bin/protoc-gen-ruby --ruby_out=#{output_dir} -I #{proto_path} #{proto_files.join(' ')})

    puts cmd
    system(cmd)

    files = {
      'tmp/rpc/dynamic_discovery.pb.rb'               => 'lib/protobuf/rpc',
      'tmp/rpc/rpc.pb.rb'                             => 'lib/protobuf/rpc',
      'tmp/rpc/google/protobuf/descriptor.pb.rb'      => 'lib/protobuf/descriptors/google/protobuf',
      'tmp/rpc/google/protobuf/compiler/plugin.pb.rb' => 'lib/protobuf/descriptors/google/protobuf/compiler',
    }

    files.each_pair do |source_file, destination_dir|
      source_file = ::File.expand_path("../#{source_file}", __FILE__)
      destination_dir = ::File.expand_path("../#{destination_dir}", __FILE__)
      ::FileUtils::Verbose.cp(source_file, destination_dir)
    end
  end

end

task :console do
  require 'pry'
  require 'protobuf'
  ARGV.clear
  ::Pry.start
end
