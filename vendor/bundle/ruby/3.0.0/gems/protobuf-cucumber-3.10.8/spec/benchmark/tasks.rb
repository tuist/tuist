require 'benchmark'
require 'protobuf'
require 'protobuf/socket'
require 'support/all'
require 'spec_helper'
require SUPPORT_PATH.join('resource_service')

case RUBY_ENGINE.to_sym
when :ruby
  require 'ruby-prof'
when :rbx
  require 'rubinius/profiler'
when :jruby
  require 'jruby/profiler'
end

# Including a way to turn on debug logger for spec runs
if ENV["DEBUG"]
  puts 'debugging'
  debug_log = File.expand_path('../../../debug_bench.log', __FILE__)
  Protobuf::Logging.initialize_logger(debug_log, ::Logger::DEBUG)
end

namespace :benchmark do

  def benchmark_wrapper(global_bench = nil)
    if global_bench
      yield global_bench
    else
      Benchmark.bm(10) do |bench|
        yield bench
      end
    end
  end

  def sock_client_sock_server(number_tests, test_length, global_bench = nil)
    load "protobuf/socket.rb"

    port = 1000 + Kernel.rand(2**16 - 1000)

    StubServer.new(:server => Protobuf::Rpc::Socket::Server, :port => port) do
      client = ::Test::ResourceService.client(:port => port)

      benchmark_wrapper(global_bench) do |bench|
        bench.report("SS / SC") do
          Integer(number_tests).times { client.find(:name => "Test Name" * Integer(test_length), :active => true) }
        end
      end
    end
  end

  def zmq_client_zmq_server(number_tests, test_length, global_bench = nil)
    load "protobuf/zmq.rb"

    port = 1000 + Kernel.rand(2**16 - 1000)

    StubServer.new(:port => port, :server => Protobuf::Rpc::Zmq::Server) do
      client = ::Test::ResourceService.client(:port => port)

      benchmark_wrapper(global_bench) do |bench|
        bench.report("ZS / ZC") do
          Integer(number_tests).times { client.find(:name => "Test Name" * Integer(test_length), :active => true) }
        end
      end
    end
  end

  desc "benchmark ZMQ client with ZMQ server"
  task :zmq_client_zmq_server, [:number, :length] do |_task, args|
    args.with_defaults(:number => 1000, :length => 100)
    zmq_client_zmq_server(args[:number], args[:length])
  end

  desc "benchmark ZMQ client with ZMQ server and profile"
  task :zmq_profile, [:number, :length, :profile_output] do |_task, args|
    args.with_defaults(:number => 1000, :length => 100, :profile_output => "/tmp/zmq_profiler_#{Time.now.to_i}")

    profile_code(args[:profile_output]) do
      zmq_client_zmq_server(args[:number], args[:length])
    end

    puts args[:profile_output]
  end

  desc "benchmark Protobuf Message #new"
  task :profile_protobuf_new, [:number, :profile_output] do |_task, args|
    args.with_defaults(:number => 1000, :profile_output => "/tmp/profiler_new_#{Time.now.to_i}")
    create_params = { :name => "The name that we set", :date_created => Time.now.to_i, :status => 2 }
    profile_code(args[:profile_output]) do
      Integer(args[:number]).times { Test::Resource.new(create_params) }
    end

    puts args[:profile_output]
  end

  desc "benchmark Protobuf Message #serialize"
  task :profile_protobuf_serialize, [:number, :profile_output] do |_task, args|
    args.with_defaults(:number => 1000, :profile_output => "/tmp/profiler_new_#{Time.now.to_i}")
    create_params = { :name => "The name that we set", :date_created => Time.now.to_i, :status => 2 }
    profile_code(args[:profile_output]) do
      Integer(args[:number]).times { Test::Resource.decode(Test::Resource.new(create_params).serialize) }
    end

    puts args[:profile_output]
  end

  def profile_code(output, &block)
    case RUBY_ENGINE.to_sym
    when :ruby
      profile_data = RubyProf.profile(&block)
      ::File.open(output, "w") do |output_file|
        RubyProf::FlatPrinter.new(profile_data).print(output_file)
      end
    when :rbx
      profiler = Rubinius::Profiler::Instrumenter.new
      profiler.profile(false, &block)
      File.open(output, 'w') do |f|
        profiler.show(f)
      end
    when :jruby
      profile_data = JRuby::Profiler.profile(&block)
      File.open(output, 'w') do |f|
        JRuby::Profiler::FlatProfilePrinter.new(profile_data).printProfile(f)
      end
    end
  end

  desc "benchmark Socket client with Socket server"
  task :sock_client_sock_server, [:number, :length] do |_task, args|
    args.with_defaults(:number => 1000, :length => 100)
    sock_client_sock_server(args[:number], args[:length])
  end

  desc "benchmark server performance"
  task :servers, [:number, :length] do |_task, args|
    args.with_defaults(:number => 1000, :length => 100)

    Benchmark.bm(10) do |bench|
      zmq_client_zmq_server(args[:number], args[:length], bench)
      sock_client_sock_server(args[:number], args[:length], bench)
    end
  end
end
