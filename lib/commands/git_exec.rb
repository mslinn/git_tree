require 'pathname'
require_relative 'abstract_command'
require_relative '../util/git_tree_walker'
require_relative '../util/thread_pool_manager'
require_relative '../util/command_runner'

module GitTree
  class ExecCommand < GitTree::AbstractCommand
    attr_writer :walker, :runner

    def initialize(args = ARGV, options: {})
      raise ArgumentError, "args must be an Array, but got #{args.class}" unless args.is_a?(Array)
      raise ArgumentError, "options must be a Hash, but got #{options.class}" unless options.is_a?(Hash)

      $PROGRAM_NAME = 'git-exec'
      super
      # Allow walker and runner to be injected for testing
      @runner = @options.delete(:runner)
      @walker = @options.delete(:walker)
    end

    def run
      setup
      return help('A SHELL_COMMAND must be specified.') if @args.empty?

      @runner ||= CommandRunner.new
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
      raise TypeError, "dir must be a String, but got #{dir.class}" unless dir.is_a?(String)
      raise TypeError, "command must be a String, but got #{command.class}" unless command.is_a?(String)

      output, status = @runner.run(command, dir)
      log_result(output, status.success?)
    rescue Errno::ENOENT
      error_message = "Error: Command '#{command}' not found"
      log_result(error_message, false)
    rescue StandardError => e
      error_message = "Error: '#{e.message}' from executing '#{command}'"
      log_result(error_message, false)
    end

    def log_result(output, success)
      raise TypeError, "output must be a String, but got #{output.class}" unless output.is_a?(String)
      raise TypeError, "success must be a Boolean, but got #{success.class}" unless [true, false].include?(success)

      return if output.strip.empty?

      if success
        # Successful command output should go to STDOUT.
        Logging.log_stdout output.strip
      else
        # Errors should go to STDERR. We use a dedicated method for this.
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

if $PROGRAM_NAME == __FILE__ || $PROGRAM_NAME.end_with?('git-exec')
  begin
    GitTree::ExecCommand.new(ARGV).run
  rescue Interrupt
    Logging.log Logging::NORMAL, "\nInterrupted by user", :yellow
    exit! 130 # Use exit! to prevent further exceptions on shutdown
  rescue StandardError => e
    Logging.log Logging::QUIET, "#{e.class}: #{e.message}\n#{e.backtrace.join("\n")}", :red
    exit 1
  end
end
