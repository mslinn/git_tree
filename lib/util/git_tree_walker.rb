require 'English'
require 'etc'
require 'shellwords'
require 'optparse'
require 'timeout'
require 'rainbow/refinement'
require_relative 'thread_pool_manager'

class GitTreeWalker
  using Rainbow

  GIT_TIMEOUT = 300 # 5 minutes max per git pull
  IGNORED_DIRECTORIES = ['.venv'].freeze
  DEFAULT_ROOTS = %w[sites sitesUbuntu work].freeze

  # Verbosity levels
  QUIET = 0
  NORMAL = 1
  VERBOSE = 2
  DEBUG = 3

  attr_reader :display_roots, :root_map

  def initialize(args = ARGV, options: {})
    @options = options
    @verbosity = @options.fetch(:verbosity, NORMAL)
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

  def log(level, msg) # Kept for external blocks to use
    return unless @verbosity >= level

    # The message might already be colored by Rainbow, so we can't just pass a color.
    # We'll just use `warn` which is thread-safe for single lines.
    msg.each_line { |line| warn line.chomp }
  end

  # A thread-safe output method for colored text to STDERR.
  def log_stderr(multiline_string, color = nil)
    multiline_string.each_line do |line|
      line_to_print = line.chomp
      line_to_print = line_to_print.public_send(color) if color
      warn line_to_print
    end
    $stderr.flush
  end

  # A thread-safe output method for uncolored text to STDOUT.
  def log_stdout(multiline_string)
    $stdout.puts multiline_string
    $stdout.flush
  end

  def process(&) # Now accepts a block
    log NORMAL, "Processing #{@display_roots.join(' ')}".green
    if @options[:serial]
      log NORMAL, "Running in serial mode.".yellow
      find_and_process_repos do |dir, _root_arg|
        yield(self, dir, 0) # Pass self as the worker for logging
      end
    else
      pool = FixedThreadPoolManager.new(0.75, verbosity: @verbosity)
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

  private

  def determine_roots(args)
    if args.empty?
      @display_roots = DEFAULT_ROOTS.map { |r| "$#{r}" }
      DEFAULT_ROOTS.each do |r|
        @root_map["$#{r}"] = ENV[r].split.map { |p| File.expand_path(p) } if ENV[r]
      end
    else
      processed_args = args.flat_map { |arg| arg.strip.split(/\s+/) }
      @display_roots = processed_args.dup
      processed_args.each do |arg|
        path = arg
        if (match = arg.match(/\A'?\$([a-zA-Z_]\w*)'?\z/))
          var_name = match[1]
          path = ENV.fetch(var_name, nil)
        end
        @root_map[arg] = [File.expand_path(path)] if path
      end
    end
  end

  def sort_directory_entries(directory_path)
    Dir.children(directory_path).select do |entry|
      File.directory?(File.join(directory_path, entry))
    end.sort
  end

  def find_git_repos_recursive(root_path, visited, &block)
    return unless File.directory?(root_path)

    return if File.exist?(File.join(root_path, '.ignore'))

    log DEBUG, "Scanning #{root_path}".yellow
    if File.exist?(File.join(root_path, '.git'))
      unless visited.include?(root_path)
        visited.add(root_path)
        yield root_path
      end
      return # Prune search
    end

    sort_directory_entries(root_path).each do |entry|
      next if IGNORED_DIRECTORIES.include?(entry)

      find_git_repos_recursive(File.join(root_path, entry), visited, &block)
    end
  rescue SystemCallError => e
    log NORMAL, "Error scanning #{root_path}: #{e.message}".red
  end
end
