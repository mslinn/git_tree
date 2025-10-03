require 'rainbow/refinement'
require 'shellwords'
require 'timeout'
require_relative 'abstract_command'
require_relative '../util/git_tree_walker'

using Rainbow

module GitTree
  class UpdateCommand < GitTree::AbstractCommand
    self.allow_empty_args = true

    def initialize(args)
      $PROGRAM_NAME = 'git-update'
      super
    end

    def run
      walker = GitTreeWalker.new(@args, verbosity: @options[:verbosity])
      walker.process do |_worker, dir, thread_id, git_walker_instance|
        abbrev_dir = git_walker_instance.abbreviate_path(dir)
        git_walker_instance.log GitTreeWalker::NORMAL, "Updating #{abbrev_dir}".green
        git_walker_instance.log GitTreeWalker::VERBOSE, "Thread #{thread_id}: git -C #{dir} pull".yellow

        output = nil
        status = nil
        begin
          Timeout.timeout(GitTreeWalker::GIT_TIMEOUT) do
            output = `git -C #{Shellwords.escape(dir)} pull 2>&1`
            status = $CHILD_STATUS.exitstatus
          end
        rescue Timeout::Error
          git_walker_instance.log GitTreeWalker::NORMAL, "[TIMEOUT] Thread #{thread_id}: git pull timed out in #{abbrev_dir}".red
          status = -1
        rescue StandardError => e
          git_walker_instance.log GitTreeWalker::NORMAL, "[ERROR] Thread #{thread_id}: Failed in #{abbrev_dir}: #{e.message}".red
          status = -1
        end

        if !status.zero?
          git_walker_instance.log GitTreeWalker::NORMAL, "[ERROR] git pull failed in #{abbrev_dir} (exit code #{status}):".red
          git_walker_instance.log GitTreeWalker::NORMAL, output.strip.red unless output.strip.empty?
        elsif git_walker_instance.instance_variable_get(:@verbosity) >= GitTreeWalker::VERBOSE
          git_walker_instance.log GitTreeWalker::NORMAL, output.strip.green
        end
      rescue Interrupt
        # This handles Ctrl-C within a worker thread, preventing a stack trace.
      end
    end

    private

    def help(msg = nil)
      warn "Error: #{msg}\n".red if msg
      warn <<~END_HELP
        git-update - Recursively updates trees of git repositories.

        If no arguments are given, uses default environment variables ('sites', 'sitesUbuntu', 'work') as roots.
        These environment variables point to roots of git repository trees to walk.
        Skips directories containing a .ignore file, and all subdirectories.

        Environment variables that point to the roots of git repository trees must have been exported, for example:

          $ export work=$HOME/work

        Usage: #{$PROGRAM_NAME} [OPTIONS] [QUOTED_ENV_VARS...]

        OPTIONS:
          -h, --help           Show this help message and exit.
          -q, --quiet          Suppress normal output, only show errors.
          -v, --verbose        Increase verbosity. Can be used multiple times (e.g., -v, -vv).

        QUOTED_ENV_VARS:
        When specifying roots, the name of the environment variable must be preceded by a dollar sign
        and enclosed within single quotes to prevent shell expansion.

        Usage examples:

        $ #{$PROGRAM_NAME}                   # Use default environment variables as roots
        $ #{$PROGRAM_NAME} '$work' '$sites'  # Use specific environment variables
      END_HELP
      exit 1
    end
  end
end

if $PROGRAM_NAME == __FILE__ || $PROGRAM_NAME.end_with?('git-update')
  begin
    GitTree::UpdateCommand.new(ARGV).run
  rescue Interrupt
    warn "\nInterrupted by user".yellow
    exit! 130 # Use exit! to prevent further exceptions on shutdown
  rescue StandardError => e
    puts "An unexpected error occurred: #{e.message}".red
    exit 1
  end
end
