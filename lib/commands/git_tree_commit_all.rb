require 'optparse'
require 'rainbow/refinement'
require 'shellwords'
require 'timeout'
require 'rugged'

require_relative 'abstract_command'
require_relative '../util/git_tree_walker'

module GitTree
  trap('INT') { exit!(-1) }
  trap('SIGINT') { exit!(-1) }
  using Rainbow

  class CommitAllCommand < AbstractCommand
    self.allow_empty_args = true

    def initialize(args)
      $PROGRAM_NAME = 'git-tree-commitAll'
      super
      @options[:message] ||= '-'
    end

    def run
      walker = GitTreeWalker.new(@args, verbosity: @options[:verbosity])
      walker.process do |_worker, dir, thread_id, git_walker_instance|
        process_repo(dir, thread_id, git_walker_instance, @options[:message])
      end
    end

    private

    def help(msg = nil)
      warn "Error: #{msg}\n".red if msg
      warn <<~END_MSG
        #{$PROGRAM_NAME} - Recursively commits and pushes changes in all git repositories under the specified DIRECTORY roots.
        If no directories are given, uses default environment variables ('sites', 'sitesUbuntu', 'work') as roots.
        Skips directories containing a .ignore file.
        Repositories in a detached HEAD state are skipped.

        Options:
          -h, --help                Show this help message and exit.
          -m, --message MESSAGE     Use the given string as the commit message.
                                    (default: "-")
          -q, --quiet               Suppress normal output, only show errors.
          -v, --verbose             Increase verbosity. Can be used multiple times (e.g., -v, -vv).

        Usage:
          #{$PROGRAM_NAME} [OPTIONS] [DIRECTORY...]

        Usage examples:
          #{$PROGRAM_NAME}                             # Commit with default message "-"
          #{$PROGRAM_NAME} -m "This is a commit message"  # Commit with a custom message
          #{$PROGRAM_NAME} '$work' '$sites'              # Commit in repositories under specific roots
      END_MSG
      exit 1
    end

    def parse_options(args)
      @args = super do |opts|
        opts.banner = "Usage: #{$PROGRAM_NAME} [options] [DIRECTORY ...]"
        opts.on("-m MESSAGE", "--message MESSAGE", "Use the given string as the commit message.") do |m|
          @options[:message] = m
        end
      end
    end

    # Processes a single git repository to check for and commit changes.
    def process_repo(dir, thread_id, git_walker_instance, message)
      short_dir = git_walker_instance.abbreviate_path(dir)
      git_walker_instance.log GitTreeWalker::VERBOSE, "Examining #{short_dir} on thread #{thread_id}".green
      begin
        # The highest priority is to check for the presence of an .ignore file.
        if File.exist?(File.join(dir, '.ignore'))
          git_walker_instance.log GitTreeWalker::DEBUG, "  Skipping #{short_dir} due to .ignore file".yellow
          return
        end

        repo = Rugged::Repository.new(dir)
        if repo.head_detached?
          git_walker_instance.log GitTreeWalker::VERBOSE, "  Skipping #{short_dir} because it is in a detached HEAD state".yellow
          return
        end

        Timeout.timeout(GitTreeWalker::GIT_TIMEOUT) do
          unless repo_has_changes?(dir)
            git_walker_instance.log GitTreeWalker::DEBUG, "  No changes to commit in #{short_dir}".yellow
            return
          end
          commit_changes(dir, message, short_dir, git_walker_instance)
        end
      rescue Timeout::Error
        git_walker_instance.log GitTreeWalker::NORMAL, "[TIMEOUT] Thread #{thread_id}: git operations timed out in #{short_dir}".red
      rescue StandardError => e
        git_walker_instance.log GitTreeWalker::NORMAL, "Error processing #{short_dir}: #{e.message}".red
        git_walker_instance.log GitTreeWalker::DEBUG, "Exception class: #{e.class}".yellow
        git_walker_instance.log GitTreeWalker::DEBUG, e.backtrace.join("\n").yellow
      end
    end

    def repo_has_staged_changes?(repo)
      # For an existing repo, diff the index against the HEAD tree.
      head_tree = repo.head.target.tree
      diff = head_tree.diff(repo.index)
      !diff.deltas.empty?
    rescue Rugged::ReferenceError # Handles a new repo with no commits yet.
      # If there's no HEAD, any file in the index is a staged change for the first commit.
      !repo.index.empty?
    end

    def commit_changes(dir, message, short_dir, git_walker_instance)
      system('git', '-C', dir, 'add', '--all', exception: true)

      repo = Rugged::Repository.new(dir)
      return unless repo_has_staged_changes?(repo)

      system('git', '-C', dir, 'commit', '-m', message, '--quiet', '--no-gpg-sign', exception: true)

      # Re-initialize the repo object to get the fresh state after the commit.
      repo = Rugged::Repository.new(dir)

      current_branch = repo.head.name.sub('refs/heads/', '')
      system('git', '-C', dir, 'push', '--set-upstream', 'origin', current_branch, exception: true)
      git_walker_instance.log GitTreeWalker::NORMAL, "Committed and pushed changes in #{short_dir}".green
    end
  end

  if $PROGRAM_NAME == __FILE__ || $PROGRAM_NAME.end_with?('git-tree-commitAll')
    begin
      GitTree::CommitAllCommand.new(ARGV).run
    rescue StandardError => e
      puts "An unexpected error occurred: #{e.message}".red
      exit 1
    end
  end
end
