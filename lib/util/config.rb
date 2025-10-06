require "anyway"
require "anyway/testing"
require_relative "log"

# See https://github.com/palkan/anyway_config?tab=readme-ov-file#usage
module GitTree
  # Enables loading config from `treeconfig.yml` (and `treeconfig.local.yml`?) files.
  # By default, Anyway! looks for yml files in
  # - `./config/treeconfig.yml`
  # - `./.treeconfig.yml`
  # - `~/.config/treeconfig.yml`
  # - `~/.treeconfig.yml`
  class GTConfig < Anyway::Config
    config_name :treeconfig
    Anyway::Settings.default_config_path = "config/treeconfig.yml"

    # All environment variables will be prefixed with `GIT_TREE_`
    env_prefix :git_tree

    # Add required attributes with default values
    attr_config git_timeout:   300,
                verbosity:     ::Logging::NORMAL,
                default_roots: %w[sites sitesUbuntu work]

    # See https://github.com/palkan/anyway_config?tab=readme-ov-file#required-options
    required :git_timeout,
             :verbosity,
             :default_roots

    # See https://github.com/palkan/anyway_config?tab=readme-ov-file#multi-env-configuration
    Anyway::Settings.future.use :unwrap_known_environments

    # See https://github.com/palkan/anyway_config?tab=readme-ov-file#source-tracing
    # Anyway::Settings.enable_source_tracing

    # On_load validators must not accept any arguments
    on_load :validate_environment
    on_load :log_environment

    private

    # Raise RuntimeError if a configuration error
    def validate_environment
      raise "The Anyway::Settings environment is not set" unless Anyway::Settings.current_environment
    end

    def log_environment
      $stdout.puts "Current environment: #{Anyway::Settings.current_environment}" if verbosity >= ::Logging::VERBOSE
    end
  end
end
