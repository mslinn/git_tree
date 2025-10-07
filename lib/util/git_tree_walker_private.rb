require_relative 'log'

class GitTreeWalker
  include Logging

  private

  # # Determines and processes root directory arguments from the command line or configuration defaults.
  #
  # This method validates +args+ as an +Array+ and raises a +TypeError+ if not. It then processes
  # the arguments: if +args+ is empty, it falls back to the +default_roots+ from the instance's
  # +@config+; otherwise, it uses +args+ directly. Each argument is stripped of leading/trailing
  # whitespace and split on whitespace to create a flattened list of individual root paths.
  #
  # The processed list is duplicated and assigned to the instance variable +@display_roots+ for
  # display/logging purposes. Finally, each processed argument is passed to +process_root_arg+
  # to handle environment variable expansion (if applicable) and store expanded absolute paths
  # in the instance variable +@root_map+ (a hash mapping original args to expanded paths).
  #
  # @param args [Array<String>] The command-line arguments representing root directories.
  # @return [void]
  # @raise [TypeError] If +args+ is not an +Array+.
  # @example
  #   # With empty args (uses defaults)
  #   determine_roots([])  # processed_args = @config.default_roots (e.g., ["$HOME/project", "/tmp"])
  #                        # @display_roots = ["$HOME/project", "/tmp"]
  #                        # Calls process_root_arg on each, populating @root_map
  #
  #   # With provided args
  #   determine_roots(["$HOME/project /tmp"])  # processed_args = ["$HOME/project", "/tmp"]
  #                                            # Same as above for @display_roots and @root_map
  def determine_roots(args)
    raise TypeError, "args must be an Array, but it was a #{args.class}" unless args.is_a?(Array)

    # If no args are provided on the command line, use the default_roots from the configuration.
    processed_args = (args.empty? ? @config.default_roots : args).flat_map { |arg| arg.strip.split(/\s+/) }
    @display_roots = processed_args.dup
    processed_args.each { |arg| process_root_arg(arg) }
  end

  # Recursively scans a directory tree for git repositories and yields their paths to a block.
  #
  # This method performs a depth-first search starting from +root_path+, identifying directories
  # containing a +.git+ subdirectory (skipping if +.git+ is a file). It yields the full path of each
  # discovered git repository to the provided block, pruning the search at each repository root
  # to avoid descending into sub-repositories. Cycles are prevented using the +visited+ set.
  #
  # Before scanning:
  # * Validates +root_path+ as a +String+ and +visited+ as a +Set+; raises +TypeError+ otherwise.
  # * Requires a block; raises +ArgumentError+ if none provided.
  # * Skips non-existent or non-directory paths.
  # * Skips directories containing a +.ignore+ file (logs at +DEBUG+ level in green).
  #
  # During scanning:
  # * Logs progress at +DEBUG+ or +NORMAL+ levels (green for info, red for errors).
  # * Ignores entries in +IGNORED_DIRECTORIES+.
  # * Processes directory entries in sorted order via +sort_directory_entries+.
  #
  # Errors during file operations (+SystemCallError+) are caught and logged at +NORMAL+ level in red,
  # allowing the scan to continue.
  #
  # @param root_path [String] The root directory path to start the recursive scan from.
  # @param visited [Set<String>] A set of visited directory paths to prevent infinite recursion.
  # @yieldparam [String] repo_path The absolute path of a discovered git repository.
  # @yieldreturn [void]
  # @return [void]
  # @raise [TypeError] If +root_path+ is not a +String+ or +visited+ is not a +Set+.
  # @raise [ArgumentError] If no block is provided.
  #
  # @example
  # visited = Set.new
  # find_git_repos_recursive("/path/to/root", visited) do |repo_path|
  #   puts "Found git repo: #{repo_path}"
  # end
  #
  # Produces this output:
  # Scanning /path/to/root
  #   Found /path/to/root/.git
  #   Found git repo: /path/to/root
  # Scanning /path/to/root/subdir
  #   Skipping /path/to/root/subdir due to .ignore file
  # Error scanning /path/to/root/invalid: No such file or directory
  def find_git_repos_recursive(root_path, visited, &block)
    raise TypeError, "root_path must be a String, but got #{root_path.class}" unless root_path.is_a?(String)
    raise TypeError, "visited must be a Set, but got #{visited.class}" unless visited.is_a?(Set)
    raise ArgumentError, "A block must be provided to #find_git_repos_recursive" unless block_given?

    return unless File.directory?(root_path)

    if File.exist?(File.join(root_path, '.ignore'))
      log DEBUG, "  Skipping #{root_path} due to .ignore file", :green
      return
    end

    log DEBUG, "Scanning #{root_path}", :green
    git_dir_or_file = File.join(root_path, '.git')
    if File.exist? git_dir_or_file
      if Dir.exist? git_dir_or_file
        log DEBUG, "  Found #{git_dir_or_file}", :green
      else
        log NORMAL, "  #{git_dir_or_file} is a file, not a directory; skipping", :green
        return
      end
      unless visited.include?(root_path)
        raise "root_path cannot be nil when yielding to find_git_repos_recursive block" if root_path.nil?

        visited.add(root_path)
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

  # Processes a root directory argument, supporting direct paths or environment variable references.
  #
  # This method handles the +arg+ parameter, which can be either:
  # * A direct filesystem path (e.g., "/home/user/project").
  # * An environment variable reference in the form +$VAR_NAME+ (unquoted) or +'$VAR_NAME'+ (quoted),
  #   where +VAR_NAME+ is a valid identifier (starts with a letter or underscore, followed by alphanumeric
  #   characters or underscores).
  #
  # If the argument matches an environment variable pattern (enforcing consistent quoting: both quotes present or both absent),
  # it extracts the variable name and fetches its value from +ENV+. If the variable is undefined, it logs an error to stderr
  # (using +Logging.log_stderr+ at +QUIET+ level, colored red) and exits with status 1.
  #
  # Regardless of the input type, if a valid +path+ is resolved, it is expanded to an absolute path
  # using +File.expand_path+ and stored in the instance variable +@root_map+ (a hash) under the
  # original +arg+ key for later reference.
  #
  # @param arg [String] The root directory argument to process.
  # @return [void]
  # @raise [SystemExit] Exits with code 1 if an environment variable is undefined.
  # @example
  # process_root_arg("/home/user/project")  # Stores expanded "/home/user/project"
  # process_root_arg("$HOME")               # Stores expanded ENV["HOME"] if defined
  # process_root_arg("'$HOME'")             # Same as above, with quotes
  # process_root_arg("$UNDEFINED")          # Logs error and exits 1
  def process_root_arg(arg)
    path = arg
    if (match = arg.match(/\A(?:'\$([a-zA-Z_]\w*)'|\$([a-zA-Z_]\w*))\z/)) # enforce consistent quoting (either 2 quotes or none)
      var_name = match[1] || match[2]
      # puts "var_name=#{var_name}"
      if var_name
        path = ENV.fetch(var_name, nil)
        unless path
          Logging.log_stderr(Logging::QUIET, "Environment variable '#{arg}' is undefined.", :red)
          exit 1
        end
      end
    end
    # puts "arg=#{arg}; path=#{path}"
    @root_map[arg] = File.expand_path(path) if path
  end

  def sort_directory_entries(directory_path)
    raise ArgumentError, "directory_path was not provided" unless directory_path
    raise TypeError, "directory_path must be a String, but it was a #{directory_path.class}" unless directory_path.is_a?(String)

    Dir.children(directory_path).select do |entry|
      File.directory?(File.join(directory_path, entry))
    end.sort
  end
end
