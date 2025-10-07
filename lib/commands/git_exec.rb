require 'pathname'
require_relative '../git_tree'

module GitTree
  class ExecCommand < GitTree::AbstractCommand
    attr_writer :walker, :runner

    # @param args [Array<String>] optional command line options
    def initialize(args = ARGV, options: {})
      raise TypeError, "args must be an Array, but it was a #{args.class}" unless args.is_a?(Array)
      raise TypeError, "options must be a Hash, but it was a #{options.class}" unless options.is_a?(Hash)

      $PROGRAM_NAME = 'git-exec'
      super
      # Allow walker and runner mocks to be injected for testing
      @runner = @options.delete(:runner)
      @walker = @options.delete(:walker)
    end

    def run
      setup
      return help('A shell command must be specified.') if @args.empty?

      # The last argument is the command to execute, the rest are roots for the walker.
      command_args = @args.length > 1 ? @args[0..-2] : []
      roots_to_walk = command_args.empty? ? @config.default_roots : command_args
      @walker ||= GitTreeWalker.new(roots_to_walk, options: @options)

      command = @args.last
      @walker.process do |dir, _thread_id, walker|
        raise "dir cannot be nil in process block" if dir.nil?
        raise TypeError, "dir must be a String in process block, but got #{dir.class}" unless dir.is_a?(String)
        raise "walker cannot be nil in process block" if walker.nil?
        unless walker.is_a?(GitTreeWalker) || walker.is_a?(RSpec::Mocks::InstanceVerifyingDouble)
          raise TypeError, "walker must be a GitTreeWalker in process block, but got #{walker.class}"
        end

        execute_and_log(dir, command)
      end
    end

    private

    def execute_and_log(dir, command)
      raise ArgumentError, "dir was not specified" unless dir
      raise ArgumentError, "command was not specified" unless command
      raise TypeError, "dir must be a String, but got #{dir.class}" unless dir.is_a?(String)
      raise TypeError, "command must be a String, but got #{command.class}" unless command.is_a?(String)

      @runner ||= CommandRunner.new # Respect a previously set mock, or create a real runner
      stdout, stderr, status = @runner.run(command, dir)
      log_result(stdout, status.success?)
      log_result(stderr, status.success?)
    rescue Errno::ENOENT
      error_message = "Error: Command '#{command}' not found"
      log_result(error_message, false)
    rescue StandardError => e
      error_message = "Error: '#{e.message}' from executing '#{command}'"
      log_result(error_message, false)
    end

    # @param output [String] The output string to log
    # @param success [Boolean] Indicates if the command executed successfully
    # @return [nil]
    def log_result(output, success)
      return unless output
      raise TypeError, "output must be a String, but it was a #{output.class}" unless output.is_a?(String)
      raise TypeError, "success must be a Boolean, but it was a #{success.class}" unless [true, false].include?(success)

      return if output.strip.empty?

      if success
        Logging.log_stdout output.strip
      else # always output this message in red
        Logging.log_stderr Logging::QUIET, output.strip, :red
      end
    end

    def help(msg = nil)
      raise TypeError, "msg must be a String or nil, but got #{msg.class}" unless msg.is_a?(String) || msg.nil?

      Logging.log(Logging::QUIET, "Error: #{msg}\n", :red) if msg
      Logging.log Logging::QUIET, <<~END_HELP
        #{$PROGRAM_NAME} - Executes an arbitrary shell command for each repository.

        If no arguments are given, uses default roots (#{@config.default_roots.join(', ')}) as roots.
        These environment variables point to roots of git repository trees to walk.
        Skips directories containing a .ignore file, and all subdirectories.

        Environment variables that point to the roots of git repository trees must have been exported, for example:

          $ export work=$HOME/work

        Usage: #{$PROGRAM_NAME} [OPTIONS] [ROOTS...] SHELL_COMMAND

        Options:
          -h, --help           Show this help message and exit.
          -q, --quiet          Suppress normal output, only show errors.
          -s, --serial         Run tasks serially in a single thread in the order specified.
          -v, --verbose        Increase verbosity. Can be used multiple times (e.g., -v, -vv).

        ROOTS can be directory names or environment variable references (e.g., '$work').
        Multiple roots can be specified in a single quoted string.

        Usage examples:
        1) For all git repositories under $sites, display their root directories:
           $ #{$PROGRAM_NAME} '$sites' pwd

        2) For all git repositories under the current directory and $my_plugins, list the `demo/` subdirectory if it exists.
           $ #{$PROGRAM_NAME} '. $my_plugins' 'if [ -d demo ]; then realpath demo; fi'

        3) For all subdirectories of the current directory, update Gemfile.lock and install a local copy of the gem:
           $ #{$PROGRAM_NAME} . 'bundle update && rake install'
      END_HELP
      exit 1
    end
  end
end
