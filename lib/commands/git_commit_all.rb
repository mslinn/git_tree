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
      # Allow walker and runner mocks to be injected for testing
      @runner = @options.delete(:runner)
      @walker = @options.delete(:walker)
    end

    # Executes the main workflow: sets up the environment, initializes components, and processes git repositories via the tree walker.
    #
    # This method orchestrates the core execution of the command.
    # It begins by invoking +setup+ (typically for logging, config, or environment preparation).
    # It ensures +@options[:message]+ defaults to +'-'+ if unset, initializes +@runner+ as a new +CommandRunner+
    # if not already present, and determines the +roots_to_walk+ from command-line arguments (+@args+) or
    # configuration defaults (+@config.default_roots+) if none provided.
    #
    # A new +GitTreeWalker+ is instantiated with the roots and options if +@walker+ is not already set.
    # It then invokes the walker's +#process+ method, providing a block that rigorously validates each yielded argument
    # (+dir+ as non-nil +String+, +thread_id+ as non-nil +Integer+, +walker+ as non-nil +GitTreeWalker+)
    # before delegating to +process_repo+ with the message from options. The walker's +#process+ handles
    # serial or multithreaded execution based on +@options[:serial]+.
    #
    # @return [void]
    # @raise [RuntimeError] If +dir+, +thread_id+, or +walker+ is +nil+ in the process block.
    # @raise [TypeError] If +dir+ is not a +String+, +thread_id+ is not an +Integer+,
    #        or +walker+ is not a +GitTreeWalker+ in the process block.
    # @example
    #   # Assuming @args = ["$HOME"], @options[:message] = "update", @options[:serial] = false
    #   run
    #   # Behavior:
    #   # - Calls setup
    #   # - Sets roots_to_walk = ["$HOME"] (expanded internally via process_root_arg)
    #   # - Initializes @walker = GitTreeWalker.new(["/home/user"], options: @options)
    #   # - @walker.process yields each discovered repo (e.g., "/home/user/repo1"), validating args
    #   # - Calls process_repo("/home/user/repo1", thread_id, walker, "update") for each in parallel
    #   # - @runner may be used internally by process_repo for command execution
    def run
      setup
      @options[:message] ||= '-'
      @runner ||= CommandRunner.new # Respect a previously set mock, or create a real runner
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
    # Parses command-line options and arguments, extracting the commit message and storing remaining directories.
    #
    # This method validates +args+ as an +Array+ and raises an +ArgumentError+ if not. It then invokes the superclass's
    # option parsing (likely +OptionParser+) with a configuration block: sets a usage banner displaying the program name
    # followed by optional directories, and defines the +-m+ or +--message+ option to capture a custom commit message string,
    # storing it in +@options[:message]+. Any non-option arguments (e.g., directory paths) are assigned to the instance
    # variable +@args+ for subsequent processing (e.g., via +#determine_roots+).
    #
    # @param args [Array<String>] The remaining command-line arguments after the AbstractCommand OptionParser has been applied.
    # @return [void]
    # @raise [ArgumentError] If +args+ is not an +Array+.
    # @example
    #   # Assuming invocation: ruby script.rb -m "Update repos" /home/user $HOME/project
    #   parse_options(["-m", "Update repos", "/home/user", "$HOME/project"])
    #   # Result:
    #   # - @options[:message] = "Update repos"
    #   # - @args = ["/home/user", "$HOME/project"] (for root processing)
    #   # Banner: "Usage: script.rb [options] [DIRECTORY ...]"
    #
    #   # No message: ruby script.rb /tmp
    #   parse_options(["/tmp"])
    #   # Result:
    #   # - @options[:message] remains default (e.g., set in #run)
    #   # - @args = ["/tmp"]
    def parse_options(args)
      raise ArgumentError, "args must be an Array, but got #{args.class}" unless args.is_a?(Array)

      @args = super do |opts|
        opts.banner = "Usage: #{$PROGRAM_NAME} [options] [DIRECTORY ...]"
        opts.on("-m MESSAGE", "--message MESSAGE", "Use the given string as the commit message.") do |m|
          @options[:message] = m
        end
      end
    end

    # Processes a single git repository: checks for skips, validates state, and commits changes if applicable.
    #
    # This method handles the core logic for a git repository at +dir+ in the context of a processing thread
    # (+thread_id+) and walker (+walker+ as +GitTreeWalker+). It first abbreviates the path for logging,
    # then logs a verbose message (green) about examination.
    # It checks for a +.ignore+ file and skips (debug log, green) if present.
    #
    # If proceeding, it opens the repository using +Rugged::Repository+ and skips (verbose log, yellow)
    # if in detached HEAD state. Within a timeout (from +walker.config.git_timeout+), it verifies changes
    # via +repo_has_changes?+; if none, skips (debug log, green).
    # If changes exist, commits them via +commit_changes+ using the provided +message+ and abbreviated path for logging.
    #
    # Timeouts (+Timeout::Error+) are rescued and logged at normal level (red). Other +StandardError+s are caught,
    # logged at normal level (red) with class/message, and backtrace dumped at debug level (red).
    #
    # Validates all arguments as specific types; raises +TypeError+ otherwise.
    #
    # @param dir [String] The absolute path of the git repository to process.
    # @param thread_id [Integer] The identifier of the current processing thread.
    # @param walker [GitTreeWalker] The GitTreeWalker instance providing configuration and abbreviation utilities.
    # @param message [String] The commit message to use if changes are committed.
    # @return [void]
    # @raise [TypeError] If +dir+ is not a +String+, +thread_id+ is not an +Integer+, +walker+ is not a +GitTreeWalker+,
    #        or +message+ is not a +String+.
    # @example
    #   # Successful commit
    #   process_repo("/home/user/repo", 1, walker, "Update files")
    #   # Logs: "Examining $HOME/repo on thread 1" (verbose, green)
    #   #       "No changes to commit in $HOME/repo" (debug, green) or proceeds to commit
    #
    #   # Skip due to .ignore
    #   process_repo("/tmp/ignored_repo", 0, walker, "-")
    #   # Logs: "Examining /tmp/ignored_repo on thread 0" (verbose, green)
    #   #       "  Skipping /tmp/ignored_repo due to .ignore file" (debug, green)
    #
    #   # Timeout error
    #   process_repo("/slow/repo", 2, walker, "Slow op")
    #   # Logs: "[TIMEOUT] Thread 2: git operations timed out in /slow/repo" (normal, red)
    #
    #   # Type error
    #   process_repo(123, 1, walker, "msg")  # Raises TypeError: dir must be a String, but got Integer
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

    # Checks if the git repository at the given directory has any uncommitted changes.
    #
    # This method validates +dir+ as a +String+ and raises a +TypeError+ if not. It opens the repository
    # using +Rugged::Repository+ and iterates over file statuses via +repo.status+. It returns +true+
    # immediately if any file has a status other than +:current+ (unchanged) or +:ignored+ (e.g., in .gitignore).
    # If all files are +:current+ or +:ignored+, it returns +false+.
    #
    # Note: This checks the working directory and index for changes; it does not consider untracked files
    # unless they are staged or modified.
    #
    # @param dir [String] The absolute path of the git repository to inspect.
    # @return [Boolean] +true+ if the repository has changes to commit, +false+ otherwise.
    # @raise [TypeError] If +dir+ is not a +String+.
    # @example
    #   repo_has_changes?("/home/user/repo")  # => true (if modified files exist)
    #   repo_has_changes?("/home/user/clean_repo")  # => false (no changes)
    #   repo_has_changes?(123)  # Raises TypeError: dir must be a String, but got Integer
    def repo_has_changes?(dir)
      raise TypeError, "dir must be a String, but got #{dir.class}" unless dir.is_a?(String)

      repo = Rugged::Repository.new(dir)
      repo.status { |_file, status| return true if status != :current && status != :ignored }
      false
    end

    # Checks if the git repository has any staged changes in the index.
    #
    # This method validates +repo+ as a +Rugged::Repository+ and raises a +TypeError+ if not. For repositories
    # with an existing HEAD (commits present), it retrieves the HEAD tree and computes the diff against the
    # current index; returns +true+ if the diff contains any deltas (indicating staged changes), +false+ otherwise.
    #
    # If the repository is new (no commits, raising +Rugged::ReferenceError+ when accessing HEAD), it checks
    # if the index contains any entries; returns +true+ if non-empty (staged for initial commit), +false+ otherwise.
    #
    # @param repo [Rugged::Repository] The git repository to inspect for staged changes.
    # @return [Boolean] +true+ if the repository has staged changes, +false+ otherwise.
    # @raise [TypeError] If +repo+ is not a +Rugged::Repository+.
    # @example
    #   repo = Rugged::Repository.new("/home/user/repo")
    #   repo_has_staged_changes?(repo)  # => true (if files staged via 'git add')
    #   repo_has_staged_changes?(new_repo)  # => true (new repo with 'git add' before first commit)
    #   repo_has_staged_changes?(clean_repo)  # => false (no staged changes)
    #   repo_has_staged_changes?(123)  # Raises TypeError: repo must be a Rugged::Repository, but got Integer
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

    # Stages all changes, commits them if staged, and pushes to the origin in the git repository.
    #
    # This method validates +dir+ (repository path), +message+ (commit message), and +short_dir+ (abbreviated path for logging)
    # as +String+s, raising +TypeError+ if not. It stages all changes using +git add --all+ (raises on failure via +exception: true+).
    #
    # It opens the repository with +Rugged::Repository+ and checks for staged changes via +repo_has_staged_changes?+; returns early
    # if none exist (no commit needed). If staged changes are present, it commits them using +git commit -m #{message} --quiet --no-gpg-sign+
    # (raises on failure). The repository is re-opened to refresh state, the current branch is extracted from +repo.head.name+ (stripping
    # +'refs/heads/'+), and the commit is pushed to +origin+ with +--set-upstream+ if not already set (raises on failure).
    #
    # On success, logs a normal-level message (green) indicating the commit and push in +short_dir+.
    #
    # @param dir [String] The absolute path of the git repository.
    # @param message [String] The commit message to use.
    # @param short_dir [String] The abbreviated path for logging purposes.
    # @return [void]
    # @raise [TypeError] If +dir+, +message+, or +short_dir+ is not a +String+.
    # @raise [SystemCallError] If any +git+ command fails (non-zero exit code).
    # @example
    #   commit_changes("/home/user/repo", "Update files", "$HOME/repo")
    #   # Behavior (assuming staged changes):
    #   # - Runs 'git -C /home/user/repo add --all'
    #   # - Runs 'git -C /home/user/repo commit -m "Update files" --quiet --no-gpg-sign'
    #   # - Extracts branch (e.g., "main"), runs 'git -C /home/user/repo push --set-upstream origin main'
    #   # - Logs: "Committed and pushed changes in $HOME/repo" (normal, green)
    #
    #   # No staged changes
    #   commit_changes("/home/user/clean_repo", "-", "$HOME/clean_repo")
    #   # - Stages changes (none), checks index, returns early (no commit/push/log)
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
