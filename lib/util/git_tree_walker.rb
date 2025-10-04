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
    @options = options
    @root_map = {}
    @display_roots = []
    determine_roots(args)
    @config = GitTree::Config.new
  end

  def abbreviate_path(dir)
    @root_map.each do |display_root, expanded_paths|
      expanded_paths.each do |expanded_path|
        return dir.sub(expanded_path, display_root) if dir.start_with?(expanded_path)
      end
    end
    dir # Return original if no match
  end

  def process(&) # Accepts a block
    log VERBOSE, "Processing #{@display_roots.join(' ')}", :green
    if @options[:serial]
      log VERBOSE, "Running in serial mode.", :yellow
      find_and_process_repos do |dir, _root_arg|
        yield(dir, 0, self) # task, thread_id, walker
      end
    else
      pool = FixedThreadPoolManager.new(0.75)
      # The block passed to pool.start now receives the walker instance (self)
      pool.start do |_worker, dir, thread_id|
        yield(dir, thread_id, self)
      end
      # Run the directory scanning in a separate thread so the main thread can handle interrupts.
      producer_thread = Thread.new do
        find_and_process_repos do |dir, _root_arg|
          pool.add_task(dir)
        end
      end

      # Wait for the producer to finish, then wait for the pool to complete.
      producer_thread.join
      pool.wait_for_completion
    end
  rescue Interrupt
    # If interrupted, ensure the pool is shut down and then let the main command handle the exit.
    pool&.shutdown
    raise
  end

  # Finds git repos and yields them to the block. Does not use thread pool.
  def find_and_process_repos(&)
    visited = Set.new
    @root_map.each do |root_arg, paths|
      paths.sort.each do |root_path|
        find_git_repos_recursive(root_path, visited) { |dir| yield(dir, root_arg) }
      end
    end
  end
end

require_relative 'git_tree_walker_private'
