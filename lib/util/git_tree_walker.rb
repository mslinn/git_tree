require 'English'
require 'etc'
require 'shellwords'
require 'optparse'
require 'timeout' # This is correct, no change needed here.
require_relative 'config'
require_relative 'log'
require_relative 'thread_pool_manager'

class GitTreeWalker
  include Logging

  attr_reader :config, :display_roots, :root_map

  IGNORED_DIRECTORIES = ['.', '..', '.venv'].freeze

  def initialize(args = ARGV, options: {})
    raise ArgumentError, "args must be an Array, but got #{args.class}" unless args.is_a?(Array)
    raise ArgumentError, "options must be a Hash, but got #{options.class}" unless options.is_a?(Hash)

    @options = options
    @config = GitTree::Config.new
    @root_map = {}
    @display_roots = []
    determine_roots(args)
  end

  def abbreviate_path(dir)
    raise TypeError, "dir must be a String, but got #{dir.class}" unless dir.is_a?(String)

    @root_map.each do |display_root, expanded_paths|
      expanded_paths.each do |expanded_path|
        return dir.sub(expanded_path, display_root) if dir.start_with?(expanded_path)
      end
    end
    dir # Return original if no match
  end

  def process(&block) # Accepts a block
    raise "A block must be provided to #process" unless block_given?
    raise "Block passed to #process must accept 3 arguments (dir, thread_id, walker)" if block.arity != 3 && block.arity >= 0

    Logging.log Logging::VERBOSE, "Processing #{@display_roots.join(' ')}", :green
    if @options[:serial]
      Logging.log Logging::VERBOSE, "Running in serial mode.", :yellow
      find_and_process_repos do |dir, _root_arg|
        raise "dir cannot be nil in find_and_process_repos block" if dir.nil?

        raise TypeError, "dir must be a String in find_and_process_repos block, but got #{dir.class}" unless dir.is_a?(String)

        raise "dir cannot be nil when yielding to process block" if dir.nil?

        yield(dir, 0, self) # task, thread_id, walker
      end
    else
      pool = FixedThreadPoolManager.new(0.75)
      # The block passed to pool.start now receives the walker instance (self)
      pool.start do |_worker, dir, thread_id|
        raise "_worker cannot be nil in pool.start block" if _worker.nil?
        raise "dir cannot be nil in pool.start block" if dir.nil?
        raise "thread_id cannot be nil in pool.start block" if thread_id.nil?

        unless _worker.is_a?(FixedThreadPoolManager)
          raise TypeError,
                "_worker must be a FixedThreadPoolManager in pool.start block, but got #{_worker.class}"
        end
        raise TypeError, "dir must be a String in pool.start block, but got #{dir.class}" unless dir.is_a?(String)
        raise TypeError, "thread_id must be an Integer in pool.start block, but got #{thread_id.class}" unless thread_id.is_a?(Integer)
        raise "thread_id cannot be nil in pool.start block" if thread_id.nil?
        raise "dir cannot be nil when yielding to process block" if dir.nil?
        raise "thread_id cannot be nil when yielding to process block" if thread_id.nil?

        yield(dir, thread_id, self)
      end
      # Find all repositories and add them to the work queue.
      # The worker threads will consume these tasks in parallel.
      find_and_process_repos do |dir, _root_arg|
        raise "dir cannot be nil in find_and_process_repos block" if dir.nil?

        raise TypeError, "dir must be a String in find_and_process_repos block, but got #{dir.class}" unless dir.is_a?(String)

        pool.add_task(dir)
      end

      pool.wait_for_completion
    end
  rescue Interrupt
    # If interrupted, ensure the pool is shut down and then let the main command handle the exit.
    pool&.shutdown
    raise
  end

  # Finds git repos and yields them to the block. Does not use thread pool.
  def find_and_process_repos(&block)
    raise "A block must be provided to #find_and_process_repos" unless block_given?
    raise "Block passed to #find_and_process_repos must accept 2 arguments (dir, root_arg)" if block.arity != 2 && block.arity >= 0

    visited = Set.new
    @root_map.each_value do |paths|
      paths.sort.each do |root_path|
        find_git_repos_recursive(root_path, visited) do |dir|
          raise "dir cannot be nil in find_git_repos_recursive block" if dir.nil?

          yield(dir, nil) # Intentionally passing nil for root_arg
        end
      end
    end
  end
end

require_relative 'git_tree_walker_private'
