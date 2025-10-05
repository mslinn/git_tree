require 'shellwords'
require 'timeout'
require_relative 'abstract_command'
require_relative '../util/git_tree_walker'
require_relative '../util/command_runner'

module GitTree
  class UpdateCommand < GitTree::AbstractCommand
    include Logging

    attr_writer :walker, :runner

    self.allow_empty_args = true

    def initialize(args = ARGV, options: {})
      raise ArgumentError, "args must be an Array, but got #{args.class}" unless args.is_a?(Array)
      raise ArgumentError, "options must be a Hash, but got #{options.class}" unless options.is_a?(Hash)

      $PROGRAM_NAME = 'git-update'
      super
      # Allow walker and runner to be injected for testing
      @runner = @options.delete(:runner)
      @walker = @options.delete(:walker)
    end

    def run
      setup
      @runner ||= CommandRunner.new
      @walker ||= GitTreeWalker.new(@args, options: @options)
      @walker.process do |dir, thread_id, walker|
        raise "dir cannot be nil in process block" if dir.nil?
        raise "thread_id cannot be nil in process block" if thread_id.nil?
        raise TypeError, "dir must be a String in process block, but got #{dir.class}" unless dir.is_a?(String)
        raise TypeError, "thread_id must be an Integer in process block, but got #{thread_id.class}" unless thread_id.is_a?(Integer)
        unless walker.is_a?(GitTreeWalker) || (walker.respond_to?(:abbreviate_path) && walker.respond_to?(:config))
          raise TypeError, "walker must be a GitTreeWalker or respond to :abbreviate_path and :config, but got #{walker.class}"
        end
        raise "walker cannot be nil in process block" if walker.nil?

        process_repo(walker, dir, thread_id)
      end
    end

    private

    def help(msg = nil)
      raise TypeError, "msg must be a String or nil, but got #{msg.class}" unless msg.is_a?(String) || msg.nil?

      Logging.log(Logging::QUIET, "Error: #{msg}\n", :red) if msg
      Logging.log Logging::QUIET, <<~END_HELP
        git-update - Recursively updates trees of git repositories.

        If no arguments are given, uses default roots (#{@config.default_roots.join(', ')}) as roots.
        These environment variables point to roots of git repository trees to walk.
        Skips directories containing a .ignore file, and all subdirectories.

        Environment variables that point to the roots of git repository trees must have been exported, for example:

          $ export work=$HOME/work

        Usage: #{$PROGRAM_NAME} [OPTIONS] [ROOTS...]

        OPTIONS:
          -h, --help           Show this help message and exit.
          -q, --quiet          Suppress normal output, only show errors.
          -v, --verbose        Increase verbosity. Can be used multiple times (e.g., -v, -vv).

        ROOTS:
        When specifying roots, directory paths can be specified, and environment variables can be used, preceded by a dollar sign.

        Usage examples:

        $ #{$PROGRAM_NAME}               # Use default environment variables as roots
        $ #{$PROGRAM_NAME} $work $sites  # Use specific environment variables
        $ #{$PROGRAM_NAME} $work /path/to/git/tree
      END_HELP
      exit 1
    end

    # Updates the git repository in the given directory.
    # @param git_walker [GitTreeWalker] The GitTreeWalker instance.
    # @param dir [String] The path to the git repository.
    # @param thread_id [Integer] The ID of the current worker thread.
    # @return [nil]
    def process_repo(git_walker, dir, thread_id)
      unless git_walker.respond_to?(:abbreviate_path) && git_walker.respond_to?(:config)
        raise ArgumentError,
              "git_walker must respond to :abbreviate_path and :config"
      end
      raise TypeError, "dir must be a String, but got #{dir.class}" unless dir.is_a?(String)
      raise TypeError, "thread_id must be an Integer, but got #{thread_id.class}" unless thread_id.is_a?(Integer)

      abbrev_dir = git_walker.abbreviate_path(dir)
      Logging.log Logging::NORMAL, "Updating #{abbrev_dir}", :green
      Logging.log Logging::VERBOSE, "Thread #{thread_id}: git -C #{dir} pull", :yellow

      output = nil
      status = nil
      begin
        Timeout.timeout(git_walker.config.git_timeout) do
          Logging.log Logging::VERBOSE, "Executing: git pull in #{dir}", :yellow
          output, status_obj = @runner.run('git pull', dir)
          status = status_obj.exitstatus
        end
      rescue Timeout::Error
        Logging.log Logging::NORMAL, "[TIMEOUT] Thread #{thread_id}: git pull timed out in #{abbrev_dir}", :red
        status = -1
      rescue StandardError => e
        Logging.log Logging::NORMAL, "[ERROR] Thread #{thread_id}: #{e.class} in #{abbrev_dir}; #{e.message}\n#{e.backtrace.join("\n")}", :red
        status = -1
      end

      if !status.zero?
        Logging.log Logging::NORMAL, "[ERROR] git pull failed in #{abbrev_dir} (exit code #{status}):", :red
        Logging.log Logging::NORMAL, output.strip, :red unless output.to_s.strip.empty?
      elsif Logging.verbosity >= Logging::VERBOSE
        # Output from a successful pull is considered NORMAL level
        Logging.log Logging::NORMAL, output.strip, :green
      end
    end
  end
end

if $PROGRAM_NAME == __FILE__ || $PROGRAM_NAME.end_with?('git-update')
  begin
    GitTree::UpdateCommand.new(ARGV).run
  rescue Interrupt
    Logging.log Logging::NORMAL, "\nInterrupted by user", :yellow
    exit! 130
  rescue StandardError => e
    Logging.log Logging::QUIET, "#{e.class}: #{e.message}\n#{e.backtrace.join("\n")}", :red
    exit! 1
  end
end
