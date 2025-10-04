require 'English'
require 'etc'
require 'shellwords'
require 'optparse'
require 'timeout'
require 'rainbow/refinement'
require_relative 'thread_pool_manager'
require_relative 'log'

class GitTreeWalker
  using Rainbow
  include Logging

  attr_reader :display_roots, :root_map

  DEFAULT_ROOTS = %w[sites sitesUbuntu work].freeze
  GIT_TIMEOUT = 10 # TODO: for debuggin only; should be 300 # 5 minutes per git pull
  IGNORED_DIRECTORIES = ['.', '..', '.venv'].freeze

  def initialize(args = ARGV, options: {})
    @options = options
    @root_map = {}
    @display_roots = []
    determine_roots(args)
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
    log_stderr VERBOSE, "Processing #{@display_roots.join(' ')}", :green
    if @options[:serial]
      log_stderr VERBOSE, "Running in serial mode.", :yellow
      find_and_process_repos do |dir, _root_arg|
        yield(self, dir, 0) # Pass self as the worker for logging
      end
    else
      pool = FixedThreadPoolManager.new(0.75)
      pool.start(&) # Pass the block to the pool's start method

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
