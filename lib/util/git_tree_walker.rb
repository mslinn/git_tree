require 'English'
require 'etc'
require 'shellwords'
require 'optparse'
require 'timeout'
require 'rainbow/refinement'
require_relative 'thread_pool_manager'

class GitTreeWalker
  using Rainbow

  GIT_TIMEOUT = 300 # 5 minutes per git pull
  IGNORED_DIRECTORIES = ['.', '..', '.venv'].freeze

  # Verbosity levels
  QUIET = 0
  NORMAL = 1
  VERBOSE = 2
  DEBUG = 3

  def initialize(args = ARGV)
    @verbosity = DEBUG
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
    puts msg if @verbosity >= level
  end

  def process(&) # Now accepts a block
    log NORMAL, "Updating #{@display_roots.join(' ')}".green
    pool = FixedThreadPoolManager.new
    pool.start do |worker, dir, thread_id|
      yield(worker, dir, thread_id, self) # Pass self (GitTreeWalker instance) for access to its methods
    end

    find_and_process_repos(pool) # This method adds tasks to the pool

    pool.shutdown
    pool.wait_for_completion
  end

  private

  def determine_roots(args)
    if args.empty?
      default_roots = %w[sites sitesUbuntu work]
      @display_roots = default_roots.map { |r| "$#{r}" }
      default_roots.each do |r|
        @root_map["$#{r}"] = ENV[r].split.map { |p| File.expand_path(p) } if ENV[r]
      end
    else
      @display_roots = args.dup
      args.each do |arg|
        path = arg
        if (match = arg.match(/\A'\$([a-zA-Z_]\w*)'\z/))
          var_name = match[1]
          path = ENV.fetch(var_name, nil)
        end
        @root_map[arg] = [File.expand_path(path)] if path
      end
    end
  end

  def find_and_process_repos(pool)
    visited = Set.new
    @root_map.each_value do |paths|
      paths.sort.each do |root_path|
        find_git_repos_recursive(root_path, visited, pool)
      end
    end
  end

  def sort_directory_entries(directory_path)
    entries = []
    directories = Dir.children(directory_path).select do |entry|
      File.directory?(File.join(directory_path, entry))
    end

    directories.each do |entry|
      entries << entry unless IGNORED_DIRECTORIES.include?(entry) # Exclude '.' and '..'
    end
    entries.sort
  end

  def find_git_repos_recursive(root_path, visited, pool)
    return unless File.directory?(root_path)

    log DEBUG, "Scanning #{root_path}".yellow
    if File.exist?(File.join(root_path, '.git'))
      unless visited.include?(root_path)
        visited.add(root_path)
        log DEBUG, "Enqueueing repo: #{root_path}".yellow
        pool.add_task(root_path)
      end
      return # Prune search
    end

    return if File.exist?(File.join(root_path, '.ignore'))

    sort_directory_entries(root_path).each do |entry|
      fq_file_name = File.join(root_path, entry)
      find_git_repos_recursive(fq_file_name, visited, pool)
    end
  rescue SystemCallError => e
    log NORMAL, "Error scanning #{root_path}: #{e.message}".red
  end
end
