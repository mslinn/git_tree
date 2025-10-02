#!/usr/bin/env ruby

# Multithreaded Ruby script to update all git directories below specified roots.

require 'etc'
require 'open3'
require 'optparse'
require 'rainbow/refinement'
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
    puts "Examining #{dir} on thread #{thread_id}".green
    rugged_repo = Rugged::Repository.new(repo)

    # Check for unstaged or staged changes
    has_changes = false
    rugged_repo.status do |_, s|
      if s != :ignored && s != :unmodified
        has_changes = true
        break
      end
    end

    unless has_changes
      puts "  No changes to commit in #{short_repo}".yellow if options[:debug]
      return
    end

    run(["git", "-C", repo, "add", "-A"], options)

    # Check again for staged changes before committing
    status_output = `git -C #{repo} status --porcelain`.strip
    if status_output.empty?
      puts "No changes to commit in #{short_repo}".yellow if options[:debug]
      return
    end

    run(["git", "-C", repo, "commit", "-m", msg, "--quiet"], options)
    puts "Committed changes in #{short_repo}".green if options[:debug]
  rescue StandardError => e
    puts "Error processing #{short_repo}: #{e.message}".red
    if options[:debug]
      puts "Exception class: #{e.class}".yellow
      puts e.backtrace.join("\n").yellow
    end
  end

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
        @root_map[arg] = [File.expand_path(arg.start_with?('$') ? (ENV[arg[1..]] || arg) : arg)]
      end
    end
  end

  def find_git_repos(root_path)
    return unless File.directory?(root_path)

    log DEBUG, "Scanning #{root_path}".yellow
    Dir.foreach(root_path) do |entry|
      next if ['.', '..'].include?(entry)

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

  def run(cmd, options)
    puts "Executing: #{cmd.join(' ')}".green if options[:debug]
    system(*cmd, exception: true)
  end

  def scan_for_repos
    @root_map.each_value do |paths|
      paths.each { |root_path| find_git_repos(root_path) }
    end
  end

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

if __FILE__ == $PROGRAM_NAME
  trap('INT') do
    exit!(-1)
  end

  trap('SIGINT') do
    exit!(-1)
  end

  begin
    updater = GitUpdater.new(ARGV)
    updater.process
  rescue StandardError => e
    puts "An unexpected error occurred: #{e.message}".red
    puts e.backtrace.join("\n").red
    exit 1
  end
end
