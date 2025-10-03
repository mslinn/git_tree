class ZoweeOptimizer
  def initialize(initial_vars = {})
    @defined_vars = {}
    initial_vars.each do |var_ref, paths| # FIXME: what are all possible values of paths? See README for desired behavior.
      var_name = var_ref.tr("'$", '')
      @defined_vars[var_name] = paths.first if paths.any?
    end
  end

  def optimize(paths, initial_roots)
    # Paths are provided in breadth-first order, so no sorting is needed.
    output = []

    paths.each do |path|
      var_name = env_var_name(File.basename(path))

      # Skip defining a var for a root that was passed in.
      next if initial_roots.include?("$#{var_name}") && @defined_vars[var_name] == path

      best_substitution = nil
      longest_match = 0

      # Find the best existing variable to substitute.
      @defined_vars.each do |sub_var, sub_path|
        if path.start_with?("#{sub_path}/") && sub_path.length > longest_match
          best_substitution = { var: sub_var, path: sub_path }
          longest_match = sub_path.length
        end
      end

      value = if best_substitution
                "$#{best_substitution[:var]}/#{path.sub("#{best_substitution[:path]}/", '')}"
              else
                path
              end

      output << "export #{var_name}=#{value}"
      @defined_vars[var_name] = path
    end

    output
  end

  def env_var_name(path)
    path.tr(' ', '_').tr('-', '_')
  end
end
