require 'open3'
require 'pathname'
require_relative 'abstract_command'
require_relative '../util/git_tree_walker'
require_relative '../util/thread_pool_manager'

module GitTree
  class ExecCommand < GitTree::AbstractCommand
    def initialize(args)
      $PROGRAM_NAME = 'git-exec'
      super
    end

    def run
      help('At least one root and a command must be specified.') if @args.length < 2

      roots = @args[0..-2]
      command = @args[-1]

      walker = GitTreeWalker.new(roots, options: @options)
      walker.process do |worker, dir, _thread_id, git_walker_instance|
        execute(worker || git_walker_instance, dir, command)
      end
    end

    private

    def execute(_worker, dir, command)
      # Call Open3.capture2e with :chdir to be thread-safe, avoiding process-wide Dir.chdir.
      # Redirect stdout and stderr to capture the output.
      output, status = Open3.capture2e(command, chdir: dir)
      if status.success?
        log(QUIET, output.strip) unless output.strip.empty?
      else
        log(QUIET, output.strip, :red) unless output.strip.empty?
      end
    rescue StandardError => e
      log QUIET, "Error: '#{e.message}' from executing '#{command}' in #{dir}", :red
    end

    def help(msg = nil)
      log(QUIET, "Error: #{msg}\n", :red) if msg
      log QUIET, <<~END_HELP
        #{$PROGRAM_NAME} - Executes an arbitrary shell command for each repository.

        If no arguments are given, uses default environment variables (#{GitTreeWalker::DEFAULT_ROOTS.join(', ')}) as roots.
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
    log NORMAL, "\nInterrupted by user", :yellow
    exit! 130 # Use exit! to prevent further exceptions on shutdown
  rescue StandardError => e
    log QUIET, "#{e.class}: #{e.message}\n#{e.backtrace.join("\n")}", :red
    exit 1
  end
end
