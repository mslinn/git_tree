require 'rainbow/refinement'
require_relative '../util/git_tree_walker'
require_relative '../util/thread_pool_manager'

module GitTree
  trap('INT') { exit!(-1) }
  trap('SIGINT') { exit!(-1) }
  using Rainbow

  begin
    $PROGRAM_NAME = 'git-tree-update'
    walker = GitTreeWalker.new ARGV
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
        git_walker_instance.log GitTreeWalker::NORMAL, "[ERROR] git pull failed in #{abbrev_dir} (exit code #{status}):\n#{output}".red
      elsif git_walker_instance.instance_variable_get(:@verbosity) >= GitTreeWalker::VERBOSE
        # The log method already handles verbosity, so we can just call it directly
        git_walker_instance.log GitTreeWalker::NORMAL, output.strip.green
      end
    end
  rescue StandardError => e
    puts "An unexpected error occurred: #{e.message}"
    puts e.backtrace.join("\n")
    exit 1
  end
end
