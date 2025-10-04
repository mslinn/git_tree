class GitTreeWalker
  using Rainbow

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
    git_dir_or_file = File.join(root_path, '.git')
    if File.exist?(git_dir_or_file)
      log DEBUG, "  Found #{git_dir_or_file}".green
      unless visited.include?(root_path)
        visited.add(root_path)
        yield root_path
      end
      return # Prune search
    else
      log DEBUG, "  No .git file/dir found in #{root_path}".blue
    end

    sort_directory_entries(root_path).each do |entry|
      next if IGNORED_DIRECTORIES.include?(entry)

      find_git_repos_recursive(File.join(root_path, entry), visited, &block)
    end
  rescue SystemCallError => e
    log NORMAL, "Error scanning #{root_path}: #{e.message}".red
  end
end
