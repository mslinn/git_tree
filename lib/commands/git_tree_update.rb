require 'rainbow/refinement'
require 'shellwords'
require 'timeout'
require_relative 'abstract_command'
require_relative '../util/git_tree_walker'
require_relative '../util/thread_pool_manager'

module GitTree
  trap('INT') { exit!(-1) }
  trap('SIGINT') { exit!(-1) }
  using Rainbow

  class UpdateCommand < AbstractCommand
    self.allow_empty_args = true

    def initialize(args)
      $PROGRAM_NAME = 'git-tree-update'
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
      end
    end

    private

    def help(msg = nil)
      warn "Error: #{msg}\n".red if msg
      warn <<~END_HELP
        git-tree-update - Recursively updates all git repositories under the specified DIRECTORY roots.
        If no directories are given, uses default environment variables ('sites', 'sitesUbuntu', 'work') as roots.
        Skips directories containing a .ignore file.

        Options:
          -h, --help           Show this help message and exit.
          -q, --quiet          Suppress normal output, only show errors.
          -v, --verbose        Verbose output.
          -vv, --very-verbose  Very verbose (debug) output.

        Usage: #{$PROGRAM_NAME} [DIRECTORY...]
      END_HELP
      exit 1
    end
  end

  if $PROGRAM_NAME == __FILE__ || $PROGRAM_NAME.end_with?('git-tree-update')
    begin
      GitTree::UpdateCommand.new(ARGV).run
    rescue StandardError => e
      puts "An unexpected error occurred: #{e.message}".red
      exit 1
    end
  end
end
