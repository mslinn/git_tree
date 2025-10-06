require 'anyway'
require_relative 'log'

module GitTree
  # Centralized configuration for the git-tree gem.
  # Uses anyway_config to load settings from:
  # 1. A YAML file at treeconfig.yml
  # 2. A YAML file at ~/.treeconfig.yml
  # 3. Environment variables (e.g., GIT_TREE_GIT_TIMEOUT)
  # 4. Default values defined here.
  # See https://github.com/palkan/anyway_config?tab=readme-ov-file#using-with-ruby
  class GTConfig < Anyway::Config
    config_name :treeconfig
    env_prefix :git_tree # Variables with name prefixes GIT_TREE_ will be parsed
    attr_config git_timeout: 300, verbosity: ::Logging::NORMAL, default_roots: %w[sites sitesUbuntu work]

    # See https://github.com/palkan/anyway_config?tab=readme-ov-file#multi-env-configuration
    config.anyway_config.future.use :unwrap_known_environments
  end
end
