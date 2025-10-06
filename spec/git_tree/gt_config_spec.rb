require "spec_helper"
require "anyway/testing"

describe GitTree::GTConfig, type: :config do
  include Anyway::Testing::Helpers

  context "when the environment is not set" do
    it "raises an error" do
      Anyway::Settings.current_environment = nil
      expect { described_class.new }.to raise_error(RuntimeError, /Anyway::Settings environment/)
    end
  end

  context "when the environment is set" do
    before do
      Anyway::Settings.current_environment = "test"
    end

    after do
      Anyway::Settings.current_environment = nil
    end

    it "does not raise an error" do
      expect { described_class.new }.not_to raise_error
    end

    it "uses the default values when no overrides are provided" do
      # This test verifies the defaults set in the GTConfig class itself.
      config = described_class.new
      expect(config.default_roots).to eq(%w[sites sitesUbuntu work])
      expect(config.git_timeout).to eq(300)
    end

    context "with yaml configuration" do
      it "overrides defaults from a simulated YAML file" do
        stub_config(default_roots: %w[c d])
        expect(described_class.new.default_roots).to eq(%w[c d])
      end

      context "when loading from a specific file path" do
        # Use a context-level around hook to cleanly manage the config_path state for this specific test.
        around do |example|
          original_path = described_class.config_path
          described_class.config_path = "spec/fixtures/treeconfig.yml"
          example.run
          described_class.config_path = original_path
        end

        it "loads configuration from that location" do
          expect(described_class.new.default_roots).to eq(%w[e f])
        end
      end
    end

    context "with environment variables" do
      it "loads configuration from environment variables" do
        stub_env("GIT_TREE_DEFAULT_ROOTS" => "g h")
        expect(described_class.new.default_roots).to eq(%w[g h])
      end

      it "prefers environment variables over YAML configuration" do
        stub_config(default_roots: %w[from file])
        stub_env("GIT_TREE_DEFAULT_ROOTS" => "from env")
        expect(described_class.new.default_roots).to eq(%w[from env])
      end
    end

    context "with source tracing" do
      before { Anyway::Settings.enable_source_tracing! }
      after { Anyway::Settings.disable_source_tracing! }

      it "traces the source of the configuration" do
        stub_config(git_timeout: 42)
        trace = described_class.new.to_source_trace["git_timeout"]
        expect(trace).to include(default: 300)
        expect(trace).to include(test: { "git_timeout" => 42 })
      end
    end

    context "with on_load callbacks" do
      # The subject is the action of initializing the config class, which triggers callbacks.
      subject(:init) { described_class.new }

      context "when verbosity is high" do
        it "logs the environment" do
          stub_config(verbosity: Logging::VERBOSE)
          expect { init }.to output(/Current environment: test/).to_stdout
        end
      end

      context "when verbosity is low" do
        it "does not log the environment" do
          stub_config(verbosity: Logging::NORMAL)
          expect { init }.not_to output.to_stdout
        end
      end
    end
  end
end
