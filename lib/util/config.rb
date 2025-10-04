require 'anyway'
require_relative 'log'

module GitTree
  # Centralized configuration for the git-tree gem.
  # Uses anyway_config to load settings from:
  # 1. A YAML file at ~/.treeconfig.yml
  # 2. Environment variables (e.g., GIT_TREE_GIT_TIMEOUT)
  # 3. Default values defined here.
  class Config < Anyway::Config
    config_name :treeconfig
    env_prefix 'GIT_TREE'

    # The location of the user's config file.
    def self.default_config_path
      File.expand_path('~/.treeconfig.yml')
    end

    # Define attributes with their default values.
    attr_config git_timeout:   300,
                verbosity:     ::Logging::NORMAL,
                default_roots: %w[sites sitesUbuntu work]
  end
end
