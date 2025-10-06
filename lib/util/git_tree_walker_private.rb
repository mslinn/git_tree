require_relative 'log'

class GitTreeWalker
  include Logging

  private

  def determine_roots(args)
    raise ArgumentError, "args must be an Array, but got #{args.class}" unless args.is_a?(Array)

    # If no args are provided on the command line, use the default_roots from the configuration.
    processed_args = (args.empty? ? @config.default_roots : args).flat_map { |arg| arg.strip.split(/\s+/) }

    @display_roots = processed_args.dup
    processed_args.each { |arg| process_root_arg(arg) }
  end

  def process_root_arg(arg)
    path = arg
    if (match = arg.match(/\A'?\$([a-zA-Z_]\w*)'?\z/))
      var_name = match[1]
      path = ENV.fetch(var_name, nil)
      unless path
        Logging.log_stderr(Logging::QUIET, "Environment variable '#{arg}' is undefined.", :red)
        exit 1
      end
    end
    @root_map[arg] = path.split.map { |p| File.expand_path(p) } if path
  end

  def sort_directory_entries(directory_path)
    raise ArgumentError, "directory_path must be a String, but got #{directory_path.class}" unless directory_path.is_a?(String)

    Dir.children(directory_path).select do |entry|
      File.directory?(File.join(directory_path, entry))
    end.sort
  end

  def find_git_repos_recursive(root_path, visited, &block)
    raise ArgumentError, "root_path must be a String, but got #{root_path.class}" unless root_path.is_a?(String)
    raise ArgumentError, "visited must be a Set, but got #{visited.class}" unless visited.is_a?(Set)
    raise "A block must be provided to #find_git_repos_recursive" unless block_given?

    return unless File.directory?(root_path)

    return if File.exist?(File.join(root_path, '.ignore'))

    log DEBUG, "Scanning #{root_path}", :green
    git_dir_or_file = File.join(root_path, '.git')
    if File.exist?(git_dir_or_file)
      log DEBUG, "  Found #{git_dir_or_file}", :green
      unless visited.include?(root_path)
        visited.add(root_path)
        raise "root_path cannot be nil when yielding to find_git_repos_recursive block" if root_path.nil?

        yield root_path
      end
      return # Prune search
    else
      log DEBUG, "  #{root_path} is not a git directory", :green
    end

    sort_directory_entries(root_path).each do |entry|
      next if IGNORED_DIRECTORIES.include?(entry)

      find_git_repos_recursive(File.join(root_path, entry), visited, &block)
    end
  rescue SystemCallError => e
    log NORMAL, "Error scanning #{root_path}: #{e.message}", :red
  end
end
