#!/usr/bin/env ruby

# Multithreaded Ruby script to update all git directories below specified roots.

require 'etc'
require 'open3'
require 'optparse'
require 'rainbow/refinement'
require 'rugged'
require 'timeout'

using Rainbow

# A class to update multiple git repositories concurrently.
class GitUpdater
  MAX_THREADS = [1, (Etc.nprocessors * 0.75).to_i].max
  GIT_TIMEOUT = 300 # 5 minutes per git pull
  DEFAULT_ROOT_VARS = %w[sites sitesUbuntu work].freeze

  # Verbosity levels
  QUIET = 0
  NORMAL = 1
  VERBOSE = 2
  DEBUG = 3

  def initialize(args)
    @mode = File.basename($PROGRAM_NAME) == 'commitAll' ? :commit : :update
    @verbosity = NORMAL
    @root_map = {}
    parse_options(args)
    determine_roots(args)
    @work_queue = Queue.new
    @processed = Set.new
  end

  def process
    action_verb = @mode == :commit ? 'Committing' : 'Updating'
    log NORMAL, "#{action_verb} #{@display_roots.join(' ')}".green
    scan_for_repos
    log VERBOSE, "Found #{@work_queue.size} repositories to process.".green
    log VERBOSE, "Using #{MAX_THREADS} threads.".green
    process_queue
    log NORMAL, "Finished processing all repositories.".blue
  end

  private

  def abbreviate_path(path)
    @root_map.each do |name, expanded_paths|
      expanded_paths.each do |expanded_path|
        return path.sub(expanded_path, name) if path.start_with?(expanded_path)
      end
    end
    path
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
  # it might contain strings that contain an environment variable reference, enclosed in single quotes
  # Here is an example: "'$work'"
  def determine_roots(args)
    if args.empty?
      @display_roots = []
      DEFAULT_ROOT_VARS.each do |var|
        next unless (path_str = ENV.fetch(var, nil))

        @display_roots << "$#{var}"
        @root_map["$#{var}"] = path_str.split.map { |p| File.expand_path(p) }
      end
    else
      @display_roots = args.dup
      args.each do |arg|
        path = arg
        if (match = arg.match(/\A'\$([a-zA-Z_]\w*)'\z/))
          var_name = match[1]
          path = ENV.fetch(var_name, nil)
        end
        expanded_path = File.expand_path(path) if path
        @root_map[arg] = [expanded_path]
      end
    end
  end

  def find_git_repos(root_path)
    return unless File.directory?(root_path)

    log DEBUG, "Scanning #{root_path}".yellow
    Dir.foreach(root_path) do |entry|
      next if ['.', '..', '.venv'].include?(entry)

      path = File.join(root_path, entry)
      next unless File.directory?(path)
      next if @processed.include?(path) # Already seen

      if File.exist?(File.join(path, '.ignore'))
        log DEBUG, "Skipping #{path} (has .ignore)".yellow
        next
      end

      if File.exist?(File.join(path, '.git'))
        @processed.add(path)
        log DEBUG, "Enqueueing repo: #{path}".yellow
        @work_queue << path
      else
        find_git_repos(path) # Recurse
      end
    end
  rescue SystemCallError => e
    log NORMAL, "Error scanning #{root_path}: #{e.message}".red
  end

  def log(level, msg)
    puts msg if @verbosity >= level
  end

  def parse_options(args)
    OptionParser.new do |opts|
      opts.banner = "Usage: #{$PROGRAM_NAME} [OPTIONS] [DIRECTORY ...]"
      opts.on('-h', '--help', 'Show this help message and exit') do
        puts opts
        exit
      end
      opts.on('-q', '--quiet', 'Suppress normal output, only show errors') { @verbosity = QUIET }
      opts.on('-v', '--verbose', 'Increase verbosity (can be repeated: -vv for debug)') { @verbosity += 1 }
    end.parse!(args)
  rescue OptionParser::InvalidOption => e
    puts "Error: #{e.message}".red
    exit!(-2)
  end

  def process_queue
    threads = Array.new(MAX_THREADS) do |i|
      Thread.new do
        while (dir = begin
          @work_queue.pop(true)
        rescue StandardError
          nil
        end)
          case @mode
          when :commit
            commit(dir, i)
          else # :update
            update_repo(dir, i)
          end
        end
      end
    end
    threads.each(&:join)
  end

  def run(cmd)
    log DEBUG, "Executing: #{cmd.join(' ')}".green
    system(*cmd, exception: true)
  end

  def scan_for_repos
    @root_map.each_value do |paths|
      paths.each { |root_path| find_git_repos(root_path) }
    end
  end

  def to_s
    msg = "#<GitUpdater"
    msg += " @mode=#{@mode} "
    msg += " @verbosity=#{@verbosity}"
    msg += " @display_roots=#{@display_roots}"
    msg += " @root_map=#{@root_map}"
    msg += " @work_queue=#{@work_queue.count}"
    msg += " @processed=#{@processed.count}"
    msg += ">"
    msg
  end

  def inspect = to_s

  def update_repo(dir, thread_id)
    abbrev_dir = abbreviate_path(dir)
    log NORMAL, "Updating #{abbrev_dir}".green
    log VERBOSE, "Thread #{thread_id}: git -C #{dir} pull".yellow

    output, status = nil
    begin
      Timeout.timeout(GIT_TIMEOUT) do
        output, status = Open3.capture2e('git', '-C', dir, 'pull')
      end
    rescue Timeout::Error
      log NORMAL, "[TIMEOUT] Thread #{thread_id}: git pull timed out in #{abbrev_dir}".red
      return
    rescue StandardError => e
      log NORMAL, "[ERROR] Thread #{thread_id}: Failed in #{abbrev_dir}: #{e}".red
      return
    end

    if status.success?
      log VERBOSE, output.strip.green unless output.strip.empty?
    else
      puts "[ERROR] git pull failed in #{abbrev_dir} (exit code #{status.exitstatus}):\n#{output}".red
    end
  end
end
