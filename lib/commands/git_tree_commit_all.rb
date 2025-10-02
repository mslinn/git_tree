require 'optparse'
require 'rainbow/refinement'
require 'rugged'

require_relative '../util/git_tree_walker'

module GitTree
  trap('INT') { exit!(-1) }
  trap('SIGINT') { exit!(-1) }
  using Rainbow

  # This class encapsulates the logic for the git-tree-commitAll command.
  class CommitAll
    def initialize(args)
      @options = {
        debug:   false,
        message: '-',
      }
      # OptionParser modifies args in place, removing parsed options.
      @args = parse_options(args)
    end

    def run
      $PROGRAM_NAME = 'git-tree-commitAll'
      walker = GitTreeWalker.new(@args) # ARGV now contains only the directory arguments
      walker.process do |_worker, dir, thread_id, git_walker_instance|
        process_repo(dir, thread_id, git_walker_instance, @options[:message])
      end
    end

    private

    def help
      puts <<~END_MSG
        Runs git commit on a tree of git repositories without prompting for messages.

        Usage: commit [options] [file...]
          Where options are:
           -d  enables debug mode
           -m "commit message"

        Examples:
          commit  # The default commit message is just a single dash (-)
          commit -m "This is a commit message"
          commit -d # Generate debug output
      END_MSG
      exit
    end

    def parse_options(args)
      OptionParser.new do |opts|
        opts.banner = "Usage: git-tree-commitAll [options] [DIRECTORY ...]"
        opts.on("-d", "--debug", "Generate debug output.") { @options[:debug] = true }
        opts.on("-h", "--help", "Show this help message and exit.") { help }
        opts.on("-m MESSAGE", "--message MESSAGE", "Use the given string as the commit message.") do |m|
          @options[:message] = m
        end
      end.parse!(args)
      args
    end

    # Processes a single git repository to check for and commit changes.
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

  begin
    GitTree::CommitAll.new(ARGV).run
  rescue StandardError => e
    puts "An unexpected error occurred: #{e.message}".red
    puts e.backtrace.join("\n")
    exit 1
  end
end
