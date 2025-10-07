require 'English'
require 'etc'
require 'shellwords'
require 'optparse'
require 'timeout'
require_relative 'config'
require_relative 'log'
require_relative 'thread_pool_manager'

class GitTreeWalker
  include Logging

  attr_reader :config, :display_roots, :root_map

  IGNORED_DIRECTORIES = ['.', '..', '.venv'].freeze

  def initialize(args = ARGV, options: {})
    raise TypeError, "args must be an Array, but got #{args.class}" unless args.is_a?(Array)
    raise TypeError, "options must be a Hash, but got #{options.class}" unless options.is_a?(Hash)

    @config = GitTree::GTConfig.new
    @display_roots = []
    @options = options
    @root_map = {}

    determine_roots(args)
  end

  # Abbreviates a directory path by replacing expanded root prefixes with their original display representations.
  #
  # This method iterates over the instance's +@root_map+ (a hash mapping display roots, e.g., "$HOME" or "'$HOME'",
  # to arrays of expanded absolute paths, e.g., ["/home/user"]). For each entry, it checks if +dir+ starts with
  # any of the expanded paths. If a match is found, it substitutes the matching prefix with the corresponding
  # display root and returns the abbreviated path immediately. If no matches are found across all entries,
  # the original +dir+ is returned unchanged.
  #
  # Validates +dir+ as a non-nil +String+; raises +ArgumentError+ if unspecified (nil) or +TypeError+ if not a +String+.
  #
  # @param dir [String] The directory path to abbreviate.
  # @return [String] The abbreviated path (with prefix replaced) or the original +dir+ if no match.
  # @raise [ArgumentError] If +dir+ is not specified (nil).
  # @raise [TypeError] If +dir+ is not a +String+.
  # @example
  #   # Assuming @root_map = {"$HOME" => ["/home/user"], "/tmp" => ["/tmp"]}
  #   abbreviate_path("/home/user/projects")  # => "$HOME/projects"
  #   abbreviate_path("/tmp/logs")            # => "/tmp/logs" (returns original if no abbreviable match)
  #   abbreviate_path("/other/path")          # => "/other/path" (no match)
  #   abbreviate_path(nil)                    # Raises ArgumentError: dir was not specified
  #   abbreviate_path(123)                    # Raises TypeError: dir must be a String, but got Integer
  def abbreviate_path(dir)
    raise ArgumentError, 'dir was not specified' unless dir
    raise TypeError, "dir must be a String, but got #{dir.class}" unless dir.is_a?(String)

    @root_map.each do |display_root, expanded_paths|
      expanded_paths.each do |expanded_path|
        return dir.sub(expanded_path, display_root) if dir.start_with?(expanded_path)
      end
    end
    dir # Return original if no match
  end

  # Finds and yields git repositories across configured roots to a provided block for processing.
  #
  # This method synchronously (without threading) scans all expanded root paths stored in the instance's
  # +@root_map+ (a hash mapping original root arguments to sorted arrays of absolute paths). For each root,
  # it invokes +find_git_repos_recursive+ with a fresh +visited+ set to discover git repositories, yielding
  # each discovered repository path (+dir+) along with its corresponding original root argument (+root_arg+)
  # to the block. The search prunes at repository boundaries and skips ignored directories/files as defined
  # in +find_git_repos_recursive+.
  #
  # Validates the block: requires it to be provided and to accept exactly two arguments (+dir+ as +String+,
  # +root_arg+ as +String+); raises a +RuntimeError+ otherwise. Also raises if a yielded +dir+ is +nil+.
  #
  # @yieldparam [String] dir The absolute path of a discovered git repository.
  # @yieldparam [String] root_arg The original root argument (e.g., "$HOME" or "'$HOME'") associated with the repository.
  # @yieldreturn [void]
  # @return [void]
  # @raise [RuntimeError] If no block is provided or the block does not accept exactly 2 arguments.
  # @raise [RuntimeError] If a yielded +dir+ is +nil+ during recursion.
  # @example
  #   find_and_process_repos do |dir, root_arg|
  #     puts "Processing repo '#{dir}' from root '#{root_arg}'"
  #   end
  #   # Assuming @root_map = {"$HOME" => ["/home/user/repo1"], "/tmp" => ["/tmp/repo2"]}
  #   # Output example:
  #   # Processing repo '/home/user/repo1' from root '$HOME'
  #   # Processing repo '/tmp/repo2' from root '/tmp'
  def find_and_process_repos(&block)
    raise "A block must be provided to #find_and_process_repos" unless block_given?
    raise "Block passed to #find_and_process_repos must accept 2 arguments (dir, root_arg)" if block.arity != 2

    visited = Set.new
    @root_map.each do |root_arg, paths|
      raise ArgumentError, "root_arg was not provided" unless root_arg
      raise ArgumentError, "paths was not provided" unless paths
      raise TypeError, "root_arg must be a String, but it was a #{root_arg.class}" unless root_arg.is_a?(String)
      raise TypeError, "paths must be an Array<String>, but it was a #{paths.class}" unless paths.is_a?(Array)

      paths.sort.each do |root_path|
        find_git_repos_recursive(root_path, visited) do |dir|
          raise "dir cannot be nil in find_git_repos_recursive block" if dir.nil?

          yield(dir, root_arg)
        end
      end
    end
  end

  # Orchestrates the processing of git repositories across configured roots, either serially or multithreaded.
  #
  # This method serves as the main entry point for processing discovered git repositories. It validates the
  # provided block, which must accept exactly three arguments: +dir+ (the repository path as +String+),
  # +thread_id+ (an identifier for the processing thread as +Integer+ or +String+), and +walker+ (a processing
  # context object). If the block's arity is non-negative and not exactly 3, or if no block is provided,
  # it raises a +RuntimeError+.
  #
  # Logs a verbose message (green) indicating the roots being processed (joined from +@display_roots+).
  # Based on the +:serial+ option in +@options+:
  # * If +true+, delegates to +process_serially+ for single-threaded execution.
  # * If +false+ (default), delegates to +process_multithreaded+ for concurrent execution.
  #
  # @yieldparam [String] dir The absolute path of a git repository to process.
  # @yieldparam thread_id The identifier of the current processing thread.
  # @yieldparam walker The processing context or walker object for the operation.
  # @yieldreturn [void]
  # @return [void]
  # @raise [RuntimeError] If no block is provided or the block does not accept exactly 3 arguments.
  # @example
  #   process do |dir, thread_id, walker|
  #     puts "Thread #{thread_id} processing #{dir} with walker: #{walker}"
  #   end
  #   # With @options[:serial] = true: Calls process_serially, logging "Processing $HOME /tmp" (verbose, green)
  #   # With @options[:serial] = false: Calls process_multithreaded for concurrent processing
  def process(&block)
    raise "A block must be provided to #process" unless block_given?
    raise "Block passed to #process must accept 3 arguments (dir, thread_id, walker)" if block.arity != 3 && block.arity >= 0

    Logging.log Logging::VERBOSE, "Processing #{@display_roots.join(' ')}", :green
    if @options[:serial]
      process_serially(&block)
    else
      process_multithreaded(&block)
    end
  end

  # Processes git repositories across configured roots using a fixed-size thread pool for concurrent execution.
  #
  # This method initializes a +FixedThreadPoolManager+ with a load factor of 0.75 (to determine pool size based on available cores),
  # starts the pool, and configures worker threads to process tasks (repository paths). Each worker receives a +dir+ (repository path),
  # +thread_id+ (integer identifier), and +self+ (the instance as the processing context or "walker"). The worker block validates its
  # arguments and yields to the provided outer block for custom processing. Interrupt signals trigger a graceful pool shutdown,
  # re-raising the exception for the main command to handle; the +ensure+ clause always shuts down the pool to release resources.
  #
  # After starting the pool, it discovers all git repositories via +find_and_process_repos+ and enqueues each +dir+ as a task
  # using +pool.add_task(dir)+. Worker threads consume these tasks in parallel. The method blocks until all tasks complete
  # via +pool.wait_for_completion+.
  #
  # Note: This is invoked when +@options[:serial]+ is +false+ in the parent +#process+ method. Extensive argument validation
  # occurs at multiple levels to ensure type safety and non-nil values.
  #
  # @yieldparam [String] dir The absolute path of a git repository to process.
  # @yieldparam [Integer] thread_id The identifier of the current worker thread.
  # @yieldparam [Object] walker The instance (+self+) serving as the processing context or walker.
  # @yieldreturn [void]
  # @return [void]
  # @raise [ArgumentError] If +worker+, +dir+, or +thread_id+ is +nil+ in the pool worker block, or +dir+ is +nil+ in the repo discovery block.
  # @raise [TypeError] If +worker+ is not a +FixedThreadPoolManager+, +dir+ is not a +String+, or +thread_id+ is not an +Integer+ in the pool worker block; or +dir+ is not a +String+ in the repo discovery block.
  # @raise [Interrupt] Re-raised after pool shutdown for external handling.
  # @example
  #   # Invoked via process with @options[:serial] = false
  #   process do |dir, thread_id, walker|
  #     puts "Thread #{thread_id} processing #{dir} with walker: #{walker}"
  #   end
  #   # Behavior:
  #   # - Starts pool with 0.75 load factor
  #   # - Enqueues discovered repos (e.g., "/home/user/repo1", "/tmp/repo2")
  #   # - Workers process in parallel, yielding to block for each
  #   # - Waits for all tasks to complete before returning
  def process_multithreaded(&)
    pool = FixedThreadPoolManager.new(0.75)
    pool.start do |worker, dir, thread_id|
      raise ArgumentError, "worker cannot be nil in pool.start block" if worker.nil?
      raise ArgumentError, "dir cannot be nil in pool.start block" if dir.nil?
      raise ArgumentError, "thread_id cannot be nil in pool.start block" if thread_id.nil?
      unless worker.is_a?(FixedThreadPoolManager)
        raise TypeError, "worker must be a FixedThreadPoolManager in pool.start block, but it was #{worker.class}"
      end
      raise TypeError, "dir must be a String in pool.start block, but it was #{dir.class}" unless dir.is_a?(String)
      raise TypeError, "thread_id must be an Integer in pool.start block, but it was #{thread_id.class}" unless thread_id.is_a?(Integer)

      yield(dir, thread_id, self)
    rescue Interrupt # ensure the pool is shut down. Let the main command handle the exit.
      pool&.shutdown
      raise
    ensure # the pool is shut down to release resources and threads.
      pool&.shutdown
    end

    # Find all repositories and add them to the work queue.
    # The worker threads will consume these tasks in parallel.
    find_and_process_repos do |dir, _root_arg|
      raise ArgumentError, "dir cannot be nil in find_and_process_repos block" if dir.nil?
      raise TypeError, "dir must be a String in find_and_process_repos block, but it was a #{dir.class}" unless dir.is_a?(String)

      pool.add_task(dir)
    end
    pool.wait_for_completion
  end

  # Processes git repositories across configured roots in single-threaded (serial) mode.
  #
  # This method logs a verbose message (yellow) indicating serial execution and then discovers all
  # git repositories via +find_and_process_repos+. For each discovered repository (+dir+), it validates
  # the path and yields it to the provided outer block along with a fixed +thread_id+ of +0+ (to mimic
  # threading consistency) and +self+ (the instance as the processing context or "walker"). Processing
  # occurs synchronously in discovery order.
  #
  # Note: Invoked when +@options[:serial]+ is +true+ in the parent +#process+ method. Argument
  # validation ensures type safety for +dir+.
  #
  # @yieldparam [String] dir The absolute path of a git repository to process.
  # @yieldparam [Integer] thread_id A fixed identifier of +0+ for serial processing.
  # @yieldparam [Object] walker The instance (+self+) serving as the processing context or walker.
  # @yieldreturn [void]
  # @return [void]
  # @raise [ArgumentError] If +dir+ is +nil+ in the repo discovery block.
  # @raise [TypeError] If +dir+ is not a +String+ in the repo discovery block.
  # @example
  #   # Invoked via process with @options[:serial] = true
  #   process do |dir, thread_id, walker|
  #     puts "Serial thread #{thread_id} processing #{dir} with walker: #{walker}"
  #   end
  #   # Behavior:
  #   # - Logs "Running in serial mode." (verbose, yellow)
  #   # - Yields each discovered repo sequentially, e.g.,
  #   #   Serial thread 0 processing /home/user/repo1 with walker: #<Object:...>
  #   #   Serial thread 0 processing /tmp/repo2 with walker: #<Object:...>
  def process_serially(&)
    Logging.log Logging::VERBOSE, "Running in serial mode.", :yellow
    find_and_process_repos do |dir, _root_arg|
      raise ArgumentError, "dir cannot be nil in find_and_process_repos block" if dir.nil?
      raise TypeError, "dir must be a String in find_and_process_repos block, but got #{dir.class}" unless dir.is_a?(String)

      yield(dir, 0, self) # task, thread_id, walker
    end
  end
end
