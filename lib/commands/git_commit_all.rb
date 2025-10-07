require 'optparse'
require 'shellwords'
require 'timeout'
require 'rugged'
require_relative '../git_tree'

module GitTree
  class CommitAllCommand < AbstractCommand
    include Logging

    attr_writer :walker

    self.allow_empty_args = true

    def initialize(args = ARGV, options: {})
      raise ArgumentError, "args must be an Array, but got #{args.class}" unless args.is_a?(Array)
      raise ArgumentError, "options must be a Hash, but got #{options.class}" unless options.is_a?(Hash)

      $PROGRAM_NAME = 'git-commitAll'
      super
      # Allow walker to be injected for testing
      @runner = @options.delete(:runner)
      @walker = @options.delete(:walker)
    end

    def run
      setup

      @options[:message] ||= '-'

      @runner ||= CommandRunner.new
      # @args should just contain roots for the walker.
      roots_to_walk = command_args.empty? ? @config.default_roots : @args
      @walker ||= GitTreeWalker.new(roots_to_walk, options: @options)
      @walker.process do |dir, thread_id, walker|
        raise "dir cannot be nil in process block" if dir.nil?
        raise "thread_id cannot be nil in process block" if thread_id.nil?
        raise "walker cannot be nil in process block" if walker.nil?

        raise TypeError, "dir must be a String in process block, but got #{dir.class}" unless dir.is_a?(String)
        raise TypeError, "thread_id must be an Integer in process block, but got #{thread_id.class}" unless thread_id.is_a?(Integer)
        raise TypeError, "walker must be a GitTreeWalker in process block, but got #{walker.class}" unless walker.is_a?(GitTreeWalker)
        raise "walker cannot be nil in process block" if walker.nil?

        process_repo(dir, thread_id, walker, @options[:message])
      end
    end

    private

    def help(msg = nil)
      raise ArgumentError, "msg must be a String or nil, but got #{msg.class}" unless msg.is_a?(String) || msg.nil?

      Logging.log(Logging::QUIET, "Error: #{msg}\n", :red) if msg
      Logging.log Logging::QUIET, <<~END_MSG
        #{$PROGRAM_NAME} - Recursively commits and pushes changes in all git repositories under the specified roots.
        If no directories are given, uses default roots (#{@config.default_roots.join(', ')}) as roots.
        Skips directories containing a .ignore file, and all subdirectories.
        Repositories in a detached HEAD state are skipped.

        Options:
          -h, --help                Show this help message and exit.
          -m, --message MESSAGE     Use the given string as the commit message.
                                    (default: "-")
          -q, --quiet               Suppress normal output, only show errors.
          -s, --serial              Run tasks serially in a single thread in the order specified.
          -v, --verbose             Increase verbosity. Can be used multiple times (e.g., -v, -vv).

        Usage:
          #{$PROGRAM_NAME} [OPTIONS] [ROOTS...]

        ROOTS can be directory names or environment variable references (e.g., '$work').
        Multiple roots can be specified in a single quoted string.

        Usage examples:
          #{$PROGRAM_NAME}                                # Commit with default message "-"
          #{$PROGRAM_NAME} -m "This is a commit message"  # Commit with a custom message
          #{$PROGRAM_NAME} $work $sites                   # Commit in repositories under specific roots
      END_MSG
      exit 1
    end

    # Provides an additional OptionParser to the base OptionParser defined in AbstractCommand.
    # @param args [Array<String>] The remaining command-line arguments after the AbstractCommand OptionParser has been applied.
    # @return [nil]
    def parse_options(args)
      raise ArgumentError, "args must be an Array, but got #{args.class}" unless args.is_a?(Array)

      @args = super do |opts|
        opts.banner = "Usage: #{$PROGRAM_NAME} [options] [DIRECTORY ...]"
        opts.on("-m MESSAGE", "--message MESSAGE", "Use the given string as the commit message.") do |m|
          @options[:message] = m
        end
      end
    end

    # Processes a single git repository to check for and commit changes.
    # @param dir [String] The path to the git repository.
    # @param thread_id [Integer] The ID of the current worker thread.
    # @param walker [GitTreeWalker] The GitTreeWalker instance.
    # @param message [String] The commit message to use.
    # @return [nil]
    def process_repo(dir, thread_id, walker, message)
      raise TypeError, "dir must be a String, but got #{dir.class}" unless dir.is_a?(String)
      raise TypeError, "thread_id must be an Integer, but got #{thread_id.class}" unless thread_id.is_a?(Integer)
      raise TypeError, "walker must be a GitTreeWalker, but got #{walker.class}" unless walker.is_a?(GitTreeWalker)
      raise TypeError, "message must be a String, but got #{message.class}" unless message.is_a?(String)

      short_dir = walker.abbreviate_path(dir)
      Logging.log Logging::VERBOSE, "Examining #{short_dir} on thread #{thread_id}", :green
      begin
        # The highest priority is to check for the presence of an .ignore file.
        if File.exist?(File.join(dir, '.ignore'))
          Logging.log Logging::DEBUG, "  Skipping #{short_dir} due to .ignore file", :green
          return
        end

        repo = Rugged::Repository.new(dir)
        if repo.head_detached?
          Logging.log Logging::VERBOSE, "  Skipping #{short_dir} because it is in a detached HEAD state", :yellow
          return
        end

        Timeout.timeout(walker.config.git_timeout) do
          unless repo_has_changes?(dir)
            Logging.log Logging::DEBUG, "  No changes to commit in #{short_dir}", :green
            return
          end
          commit_changes(dir, message, short_dir)
        end
      rescue Timeout::Error
        Logging.log Logging::NORMAL, "[TIMEOUT] Thread #{thread_id}: git operations timed out in #{short_dir}", :red
      rescue StandardError => e
        Logging.log Logging::NORMAL, "#{e.class} processing #{short_dir}: #{e.message}", :red
        e.backtrace.join("\n").each_line { |line| Logging.log Logging::DEBUG, line, :red }
      end
    end

    # @return [Boolean] True if the repository has changes, false otherwise.
    def repo_has_changes?(dir)
      raise TypeError, "dir must be a String, but got #{dir.class}" unless dir.is_a?(String)

      repo = Rugged::Repository.new(dir)
      repo.status { |_file, status| return true if status != :current && status != :ignored }
      false
    end

    # @param dir [String] The path to the git repository.
    # @return [Boolean] True if the repository has changes, false otherwise.
    def repo_has_staged_changes?(repo)
      raise TypeError, "repo must be a Rugged::Repository, but got #{repo.class}" unless repo.is_a?(Rugged::Repository)

      # For an existing repo, diff the index against the HEAD tree.
      head_tree = repo.head.target.tree
      diff = head_tree.diff(repo.index)
      !diff.deltas.empty?
    rescue Rugged::ReferenceError # Handles a new repo with no commits yet.
      # If there's no HEAD, any file in the index is a staged change for the first commit.
      !repo.index.empty?
    end

    # @param dir [String] The path to the git repository.
    # @param message [String] The commit message to use.
    # @param short_dir [String] The shortened path to the git repository.
    # @return [nil]
    def commit_changes(dir, message, short_dir)
      raise TypeError, "dir must be a String, but got #{dir.class}" unless dir.is_a?(String)
      raise TypeError, "message must be a String, but got #{message.class}" unless message.is_a?(String)
      raise TypeError, "short_dir must be a String, but got #{short_dir.class}" unless short_dir.is_a?(String)

      system('git', '-C', dir, 'add', '--all', exception: true)

      repo = Rugged::Repository.new(dir)
      return unless repo_has_staged_changes?(repo)

      system('git', '-C', dir, 'commit', '-m', message, '--quiet', '--no-gpg-sign', exception: true)

      # Re-initialize the repo object to get the fresh state after the commit.
      repo = Rugged::Repository.new(dir)

      current_branch = repo.head.name.sub('refs/heads/', '')
      system('git', '-C', dir, 'push', '--set-upstream', 'origin', current_branch, exception: true)
      Logging.log Logging::NORMAL, "Committed and pushed changes in #{short_dir}", :green
    end
  end
end

if $PROGRAM_NAME == __FILE__ || $PROGRAM_NAME.end_with?('git-commitAll') # Corrected from git-tree-commitAll
  begin
    GitTree::CommitAllCommand.new(ARGV).run
  rescue Interrupt
    Logging.log Logging::NORMAL, "\nInterrupted by user", :yellow
    exit! 130 # Use exit! to prevent further exceptions on shutdown
  rescue StandardError => e
    Logging.log Logging::QUIET, "#{e.class}: #{e.message}\n#{e.backtrace.join("\n")}", :red
    exit 1
  end
end
