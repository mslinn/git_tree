class ZoweeOptimizer
  # The ZoweeOptimizer class is responsible for optimizing the environment variable definitions.
  # It is used by the `git-evars` command to generate a script with shorter and more readable variable names.
  def initialize(initial_vars = {})
    @defined_vars = {}
    initial_vars.each do |var_ref, paths|
      var_name = var_ref.tr("'$", '')
      @defined_vars[var_name] = paths.first if paths.any?
    end
  end

  # Optimizes a list of paths to generate a script with environment variable definitions.
  # @param paths [Array<String>] are provided in breadth-first order, so no sorting is needed.
  # @param initial_roots [Array<String>] a list of initial root variables.
  # @return [Array<String>] a list of strings, where each string is an export statement for an environment variable.
  def optimize(paths, initial_roots)
    output = []

    # Find common prefixes and define intermediate variables
    define_intermediate_vars(paths)

    paths.each do |path|
      var_name = generate_var_name(path)
      next if var_name.nil?

      # Skip defining a var for a root that was passed in.
      next if initial_roots.include?("$#{var_name}") && @defined_vars[var_name] == path

      best_substitution = find_best_substitution(path)

      value = if best_substitution
                "$#{best_substitution[:var]}/#{path.sub("#{best_substitution[:path]}/", '')}"
              else
                path
              end

      output << "export #{var_name}=#{value}"
      @defined_vars[var_name] = path
    end

    (@intermediate_vars.values + output).uniq
  end

  # Generates a valid environment variable name from a path.
  # @param path [String] the path to generate the variable name from.
  # @return [String] a valid environment variable name.
  def generate_var_name(path)
    basename = File.basename(path)
    return nil if basename.empty?

    parts = basename.split('.')
    name = if parts.first == 'www' && parts.length > 1
             parts[1]
           else
             parts.first
           end.tr('-', '_')

    if @defined_vars.key?(name) && @defined_vars[name] != path
      # Collision. Try to disambiguate.
      parent_name = File.basename(File.dirname(path))
      name = "#{parent_name}_#{name}"
    end

    # Sanitize the name
    name.gsub!(/[^a-zA-Z0-9_]/, '_')

    # Prepend underscore if it starts with a digit
    name = "_#{name}" if name.match?(/^[0-9]/)

    name
  end

  private

  # Defines intermediate variables based on common prefixes in the given paths.
  # @param paths [Array<String>] a list of paths.
  def define_intermediate_vars(paths)
    @intermediate_vars = {}
    prefixes = {}
    paths.each do |path|
      parts = path.split('/')
      (1...parts.length).each do |i|
        prefix = parts.take(i).join('/')
        prefixes[prefix] ||= 0
        prefixes[prefix] += 1
      end
    end

    # Sort by length to define shorter prefixes first
    sorted_prefixes = prefixes.keys.sort_by(&:length)

    sorted_prefixes.each do |prefix|
      # An intermediate variable is useful if it is a prefix to at least 2 paths
      # and is not one of the paths to be defined.
      # Also, it should not be created if a more specific path from the input list can be used.
      is_useful = prefixes[prefix] > 1 &&
                  !@defined_vars.value?(prefix) &&
                  paths.none? { |p| File.dirname(p) == prefix } &&
                  @defined_vars.values.compact.none? { |v| prefix.start_with?(v) || v.start_with?(prefix) }
      is_not_an_input_path = !paths.include?(prefix)
      next unless is_useful && is_not_an_input_path

      var_name = generate_var_name(prefix)
      next if var_name.nil?

      best_substitution = find_best_substitution(prefix)
      value = if best_substitution
                "$#{best_substitution[:var]}/#{prefix.sub("#{best_substitution[:path]}/", '')}"
              else
                prefix
              end

      unless @defined_vars.key?(var_name)
        @defined_vars[var_name] = prefix
        @intermediate_vars[prefix] = "export #{var_name}=#{value}"
      end
    end
  end

  # Finds the best substitution for a given path from the currently defined variables.
  # @param path [String] the path to find the best substitution for.
  # @return [Hash] a hash containing the best substitution variable and path, or nil if no substitution is found.
  def find_best_substitution(path)
    best_substitution = nil
    longest_match = 0

    # Find the best existing variable to substitute.
    @defined_vars.each do |sub_var, sub_path|
      if path.start_with?("#{sub_path}/") && sub_path.length > longest_match
        best_substitution = { var: sub_var, path: sub_path }
        longest_match = sub_path.length
      end
    end
    best_substitution
  end
end
