require 'cli/kit'

require 'open3'
require 'English'

module CLI
  module Kit
    module System
      SUDO_PROMPT = CLI::UI.fmt("{{info:(sudo)}} Password: ")
      class << self
        # Ask for sudo access with a message explaning the need for it
        # Will make subsequent commands capable of running with sudo for a period of time
        #
        # #### Parameters
        # - `msg`: A message telling the user why sudo is needed
        #
        # #### Usage
        # `ctx.sudo_reason("We need to do a thing")`
        #
        def sudo_reason(msg)
          # See if sudo has a cached password
          `env SUDO_ASKPASS=/usr/bin/false sudo -A true`
          return if $CHILD_STATUS.success?
          CLI::UI.with_frame_color(:blue) do
            puts(CLI::UI.fmt("{{i}} #{msg}"))
          end
        end

        # Execute a command in the user's environment
        # This is meant to be largely equivalent to backticks, only with the env passed in.
        # Captures the results of the command without output to the console
        #
        # #### Parameters
        # - `*a`: A splat of arguments evaluated as a command. (e.g. `'rm', folder` is equivalent to `rm #{folder}`)
        # - `sudo`: If truthy, run this command with sudo. If String, pass to `sudo_reason`
        # - `env`: process environment with which to execute this command
        # - `**kwargs`: additional arguments to pass to Open3.capture2
        #
        # #### Returns
        # - `output`: output (STDOUT) of the command execution
        # - `status`: boolean success status of the command execution
        #
        # #### Usage
        # `out, stat = CLI::Kit::System.capture2('ls', 'a_folder')`
        #
        def capture2(*a, sudo: false, env: ENV, **kwargs)
          delegate_open3(*a, sudo: sudo, env: env, method: :capture2, **kwargs)
        end

        # Execute a command in the user's environment
        # This is meant to be largely equivalent to backticks, only with the env passed in.
        # Captures the results of the command without output to the console
        #
        # #### Parameters
        # - `*a`: A splat of arguments evaluated as a command. (e.g. `'rm', folder` is equivalent to `rm #{folder}`)
        # - `sudo`: If truthy, run this command with sudo. If String, pass to `sudo_reason`
        # - `env`: process environment with which to execute this command
        # - `**kwargs`: additional arguments to pass to Open3.capture2e
        #
        # #### Returns
        # - `output`: output (STDOUT merged with STDERR) of the command execution
        # - `status`: boolean success status of the command execution
        #
        # #### Usage
        # `out_and_err, stat = CLI::Kit::System.capture2e('ls', 'a_folder')`
        #
        def capture2e(*a, sudo: false, env: ENV, **kwargs)
          delegate_open3(*a, sudo: sudo, env: env, method: :capture2e, **kwargs)
        end

        # Execute a command in the user's environment
        # This is meant to be largely equivalent to backticks, only with the env passed in.
        # Captures the results of the command without output to the console
        #
        # #### Parameters
        # - `*a`: A splat of arguments evaluated as a command. (e.g. `'rm', folder` is equivalent to `rm #{folder}`)
        # - `sudo`: If truthy, run this command with sudo. If String, pass to `sudo_reason`
        # - `env`: process environment with which to execute this command
        # - `**kwargs`: additional arguments to pass to Open3.capture3
        #
        # #### Returns
        # - `output`: STDOUT of the command execution
        # - `error`: STDERR of the command execution
        # - `status`: boolean success status of the command execution
        #
        # #### Usage
        # `out, err, stat = CLI::Kit::System.capture3('ls', 'a_folder')`
        #
        def capture3(*a, sudo: false, env: ENV, **kwargs)
          delegate_open3(*a, sudo: sudo, env: env, method: :capture3, **kwargs)
        end

        # Execute a command in the user's environment
        # Outputs result of the command without capturing it
        #
        # #### Parameters
        # - `*a`: A splat of arguments evaluated as a command. (e.g. `'rm', folder` is equivalent to `rm #{folder}`)
        # - `sudo`: If truthy, run this command with sudo. If String, pass to `sudo_reason`
        # - `env`: process environment with which to execute this command
        # - `**kwargs`: additional keyword arguments to pass to Process.spawn
        #
        # #### Returns
        # - `status`: boolean success status of the command execution
        #
        # #### Usage
        # `stat = CLI::Kit::System.system('ls', 'a_folder')`
        #
        def system(*a, sudo: false, env: ENV, **kwargs)
          a = apply_sudo(*a, sudo)

          out_r, out_w = IO.pipe
          err_r, err_w = IO.pipe
          in_stream = STDIN.closed? ? :close : STDIN
          pid = Process.spawn(env, *resolve_path(a, env), 0 => in_stream, :out => out_w, :err => err_w, **kwargs)
          out_w.close
          err_w.close

          handlers = if block_given?
            { out_r => ->(data) { yield(data.force_encoding(Encoding::UTF_8), '') },
              err_r => ->(data) { yield('', data.force_encoding(Encoding::UTF_8)) } }
          else
            { out_r => ->(data) { STDOUT.write(data) },
              err_r => ->(data) { STDOUT.write(data) } }
          end

          previous_trailing = Hash.new('')
          loop do
            ios = [err_r, out_r].reject(&:closed?)
            break if ios.empty?

            readers, = IO.select(ios)
            readers.each do |io|
              begin
                data, trailing = split_partial_characters(io.readpartial(4096))
                handlers[io].call(previous_trailing[io] + data)
                previous_trailing[io] = trailing
              rescue IOError
                io.close
              end
            end
          end

          Process.wait(pid)
          $CHILD_STATUS
        end

        # Split off trailing partial UTF-8 Characters. UTF-8 Multibyte characters start with a 11xxxxxx byte that tells
        # how many following bytes are part of this character, followed by some number of 10xxxxxx bytes.  This simple
        # algorithm will split off a whole trailing multi-byte character.
        def split_partial_characters(data)
          last_byte = data.getbyte(-1)
          return [data, ''] if (last_byte & 0b1000_0000).zero?

          # UTF-8 is up to 6 characters per rune, so we could never want to trim more than that, and we want to avoid
          # allocating an array for the whole of data with bytes
          min_bound = -[6, data.bytesize].min
          final_bytes = data.byteslice(min_bound..-1).bytes
          partial_character_sub_index = final_bytes.rindex { |byte| byte & 0b1100_0000 == 0b1100_0000 }
          # Bail out for non UTF-8
          return [data, ''] unless partial_character_sub_index
          partial_character_index = min_bound + partial_character_sub_index

          [data.byteslice(0...partial_character_index), data.byteslice(partial_character_index..-1)]
        end

        private

        def apply_sudo(*a, sudo)
          a.unshift('sudo', '-S', '-p', SUDO_PROMPT, '--') if sudo
          sudo_reason(sudo) if sudo.is_a?(String)
          a
        end

        def delegate_open3(*a, sudo: raise, env: raise, method: raise, **kwargs)
          a = apply_sudo(*a, sudo)
          Open3.send(method, env, *resolve_path(a, env), **kwargs)
        rescue Errno::EINTR
          raise(Errno::EINTR, "command interrupted: #{a.join(' ')}")
        end

        # Ruby resolves the program to execute using its own PATH, but we want it to
        # use the provided one, so we ensure ruby chooses to spawn a shell, which will
        # parse our command and properly spawn our target using the provided environment.
        #
        # This is important because dev clobbers its own environment such that ruby
        # means /usr/bin/ruby, but we want it to select the ruby targeted by the active
        # project.
        #
        # See https://github.com/Shopify/dev/pull/625 for more details.
        def resolve_path(a, env)
          # If only one argument was provided, make sure it's interpreted by a shell.
          return ["true ; " + a[0]] if a.size == 1
          return a if a.first.include?('/')

          paths = env.fetch('PATH', '').split(':')
          item = paths.detect do |f|
            command_path = "#{f}/#{a.first}"
            File.executable?(command_path) && File.file?(command_path)
          end

          a[0] = "#{item}/#{a.first}" if item
          a
        end
      end
    end
  end
end
