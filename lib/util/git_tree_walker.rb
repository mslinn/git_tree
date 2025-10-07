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

  # Finds git repos and yields them to the block. Does not use a thread pool.
  def find_and_process_repos(&block)
    raise "A block must be provided to #find_and_process_repos" unless block_given?
    raise "Block passed to #find_and_process_repos must accept 2 arguments (dir, root_arg)" if block.arity != 2

    visited = Set.new
    @root_map.each do |root_arg, paths|
      paths.sort.each do |root_path|
        find_git_repos_recursive(root_path, visited) do |dir|
          raise "dir cannot be nil in find_git_repos_recursive block" if dir.nil?

          yield(dir, root_arg)
        end
      end
    end
  end

  def process(&block) # Accepts a block
    raise "A block must be provided to #process" unless block_given?
    raise "Block passed to #process must accept 3 arguments (dir, thread_id, walker)" if block.arity != 3 && block.arity >= 0

    Logging.log Logging::VERBOSE, "Processing #{@display_roots.join(' ')}", :green
    if @options[:serial]
      process_serially(&block)
    else
      process_multithreaded(&block)
    end
  end

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

  def process_serially(&)
    Logging.log Logging::VERBOSE, "Running in serial mode.", :yellow
    find_and_process_repos do |dir, _root_arg|
      raise ArgumentError, "dir cannot be nil in find_and_process_repos block" if dir.nil?
      raise TypeError, "dir must be a String in find_and_process_repos block, but got #{dir.class}" unless dir.is_a?(String)

      yield(dir, 0, self) # task, thread_id, walker
    end
  end
end
