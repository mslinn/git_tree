require "spec_helper"
require "anyway/testing"

describe GitTree::GTConfig, type: :config do
  include Anyway::Testing::Helpers

  let(:config) { described_class.new }

  # Reset to default config before each example
  around do |ex|
    with_config(default_roots: %w[a b]) do
      x = ex.run
      puts "x is a #{x.class.name}"
    end
  end

  context "when the environment is not set" do
    it "raises an error" do
      Anyway::Settings.current_environment = nil
      expect { config }.to raise_error(RuntimeError, /Anyway::Settings environment/)
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
      expect { config }.not_to raise_error
    end

    context "with yaml configuration" do
      it "loads configuration from a YAML file" do
        with_config(default_roots: %w[c d]) do
          expect(config.default_roots).to eq(%w[c d])
        end
      end

      it "loads configuration from a YAML file with a specific location" do
        with_config_path("spec/fixtures/treeconfig.yml") do
          expect(config.default_roots).to eq(%w[e f])
        end
      end
    end

    context "with environment variables" do
      it "loads configuration from environment variables" do
        with_env("GIT_TREE_DEFAULT_ROOTS" => "g h") do
          expect(config.default_roots).to eq(%w[g h])
        end
      end
    end

    context "with source tracing" do
      it "traces the source of the configuration" do
        with_config(default_roots: %w[c d]) do
          expect(config.to_source_trace["default_roots"]).to eq(default: %w[a b], test: { "default_roots" => %w[c d] })
        end
      end
    end
  end
end
