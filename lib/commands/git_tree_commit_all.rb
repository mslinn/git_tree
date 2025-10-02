require 'optparse'
require 'rainbow/refinement'
require 'rugged'

require_relative 'abstract_command'
require_relative '../util/git_tree_walker'

module GitTree
  trap('INT') { exit!(-1) }
  trap('SIGINT') { exit!(-1) }
  using Rainbow

  class CommitAllCommand < AbstractCommand
    def initialize(args) # rubocop:disable Lint/MissingSuper
      $PROGRAM_NAME = 'git-tree-commitAll'
      # Don't call super, as this command has special arg handling
      # (it can run without directory arguments).
      @options = { verbosity: GitTreeWalker::NORMAL }
      parse_options(args)
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
        git-tree-commitAll - Runs git commit on a tree of git repositories without prompting for messages.

        Recursively commits changes in all git repositories under the specified DIRECTORY roots.
        If no directories are given, uses default environment variables ('sites', 'sitesUbuntu', 'work') as roots.
        Skips directories containing a .ignore file.

        Usage: #{$PROGRAM_NAME} [options] [DIRECTORY...]

        Options:
          -h, --help                Show this help message and exit.
          -m, --message MESSAGE     Use the given string as the commit message.
          -q, --quiet               Suppress normal output, only show errors.
          -v, --verbose             Verbose output.
          -vv, --very-verbose       Very verbose (debug) output.

        Examples:
          #{$PROGRAM_NAME}  # The default commit message is just a single dash (-)
          #{$PROGRAM_NAME} -m "This is a commit message"
          #{$PROGRAM_NAME} '$work' '$sites'
      END_MSG
      exit 0
    end

    def parse_options(args)
      parser = super do |opts|
        opts.banner = "Usage: #{$PROGRAM_NAME} [options] [DIRECTORY ...]"
        opts.on("-m MESSAGE", "--message MESSAGE", "Use the given string as the commit message.") do |m|
          @options[:message] = m
        end
      end
      @args = parser.parse!(args)
    end

    # Processe a single git repository to check for and commit changes.
    def process_repo(dir, thread_id, git_walker_instance, message)
      short_dir = git_walker_instance.abbreviate_path(dir)
      git_walker_instance.log GitTreeWalker::VERBOSE, "Examining #{short_dir} on thread #{thread_id}".green
      begin # Check if there are changes to commit in the repo at 'dir'
        status_output = `git -C #{Shellwords.escape(dir)} status --porcelain`
        has_changes = !status_output.strip.empty?
        unless has_changes
          git_walker_instance.log GitTreeWalker::DEBUG, "  No changes to commit in #{short_dir}".yellow
          return
        end
        system('git', '-C', dir, 'add', '--all', exception: true)
        system('git', '-C', dir, 'commit', '-m', message, '--quiet', exception: true)
        git_walker_instance.log GitTreeWalker::NORMAL, "Committed changes in #{short_dir}".green
      rescue StandardError => e
        git_walker_instance.log GitTreeWalker::NORMAL, "Error processing #{short_dir}: #{e.message}".red
        git_walker_instance.log GitTreeWalker::DEBUG, "Exception class: #{e.class}".yellow
        git_walker_instance.log GitTreeWalker::DEBUG, e.backtrace.join("\n").yellow
      end
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
