#!/usr/bin/env ruby

require 'English'
require 'etc'
require 'shellwords'
require 'optparse'
require 'timeout'
require 'rainbow/refinement'
require_relative 'thread_pool_manager'

class GitUpdater
  using Rainbow

  GIT_TIMEOUT = 300 # 5 minutes per git pull

  # Verbosity levels
  QUIET = 0
  NORMAL = 1
  VERBOSE = 2
  DEBUG = 3

  def initialize(args = ARGV)
    @verbosity = NORMAL
    @root_map = {}
    @display_roots = []
    determine_roots(args)
  end

  def process
    log NORMAL, "Updating #{@display_roots.join(' ')}".green
    pool = FixedThreadPoolManager.new
    pool.start do |_worker, dir, thread_id|
      update_repo(dir, thread_id)
    end

    find_and_process_repos(pool)

    pool.shutdown
    pool.wait_for_completion
  end

  private

  def abbreviate_path(dir)
    @root_map.each do |display_root, expanded_paths|
      expanded_paths.each do |expanded_path|
        return dir.sub(expanded_path, display_root) if dir.start_with?(expanded_path)
      end
    end
    dir # Return original if no match
  end

  def commit(dir, thread_id)
    short_dir = abbreviate_path(dir)
    log VERBOSE, "Examining #{short_dir} on thread #{thread_id}".green
    rugged_repo = Rugged::Repository.new(dir)

    # Check for unstaged or staged changes
    has_changes = false
    rugged_repo.status do |_, s|
      unless %i[ignored unmodified].include?(s)
        has_changes = true
        break
      end
    end

    unless has_changes
      log DEBUG, "  No changes to commit in #{short_dir}".yellow
      return
    end

    run(['git', '-C', dir, 'add', '-A'])

    # Check again for staged changes before committing
    status_output = `git -C #{dir} status --porcelain`.strip
    if status_output.empty?
      log DEBUG, "No changes to commit in #{short_dir}".yellow
      return
    end

    run(['git', '-C', dir, 'commit', '-m', 'Auto-commit by git-tree-commitAll', '--quiet'])
    log NORMAL, "Committed changes in #{short_dir}".green
  rescue StandardError => e
    log NORMAL, "Error processing #{short_dir}: #{e.message}".red
    log DEBUG, "Exception class: #{e.class}".yellow
    log DEBUG, e.backtrace.join("\n").yellow
  end

  # args might contain literal file paths or
  # environment variables that point to file paths
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
      paths.each do |root_path|
        find_git_repos_recursive(root_path, visited, pool)
      end
    end
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

    Dir.foreach(root_path) do |entry|
      next if ['.', '..'].include?(entry)

      find_git_repos_recursive(File.join(root_path, entry), visited, pool)
    end
  rescue SystemCallError => e
    log NORMAL, "Error scanning #{root_path}: #{e.message}".red
  end

  def log(level, msg)
    puts msg if @verbosity >= level
  end

  def run(cmd)
    log DEBUG, "Executing: #{cmd.join(' ')}".green
    system(*cmd, exception: true)
  end

  def update_repo(dir, thread_id)
    abbrev_dir = abbreviate_path(dir)
    log NORMAL, "Updating #{abbrev_dir}".green
    log VERBOSE, "Thread #{thread_id}: git -C #{dir} pull".yellow

    output = nil
    status = nil
    begin
      Timeout.timeout(GIT_TIMEOUT) do
        output = `git -C #{Shellwords.escape(dir)} pull 2>&1`
        status = $CHILD_STATUS.exitstatus
      end
    rescue Timeout::Error
      log NORMAL, "[TIMEOUT] Thread #{thread_id}: git pull timed out in #{abbrev_dir}".red
      status = -1
    rescue StandardError => e
      log NORMAL, "[ERROR] Thread #{thread_id}: Failed in #{abbrev_dir}: #{e}".red
      status = -1
    end

    if status != 0
      log NORMAL, "[ERROR] git pull failed in #{abbrev_dir} (exit code #{status}):\n#{output}".red
    elsif @verbosity >= VERBOSE
      log NORMAL, output.strip.green
    end
  end
end
