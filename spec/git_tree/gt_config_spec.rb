require_relative '../spec_helper'

describe GitTree::GTConfig, type: :config do
  # See: https://github.com/palkan/anyway_config/blob/master/lib/anyway/testing.rb

  context "when the environment is not set" do
    Anyway::Settings.current_environment = nil
    it "raises an error" do
      Anyway::Settings.current_environment = nil
      expect { config }.to raise_error(RuntimeError, /Anyway::Settings environment/)
    end
  end

  context "when the environment is set" do
    Anyway::Settings.current_environment = 'test'
    it "does not raise an error" do
      expect { config }.not_to raise_error
    end
  end

  context "with attributes" do
    Anyway::Settings.current_environment = 'test'
    config = described_class.new
    config.load_from_sources([
                               { type: :yml }, # Loads from this YAML file
                               { type: :env }  # Then overrides from ENV (e.g., MYAPP_HOST)
                             ], config_path: 'config/treeconfig.yml')

    it "#git_timeout" do
      expect(config).to respond_to(:git_timeout)

      source = git_timeout[:source]
      expect(source).to eq({
                             type: :yml,
                             key:  'production',
                           })
      expect(value).to eq({
                            git_timeout:   300,
                            verbosity:     1,
                            default_roots: [sites, sitesUbuntu, work],
                          })

      git_timeout = config.to_source_trace['git_timeout']
      expect(git_timeout).to eq?(7)
    end

    it "#verbosity" do
      expect(config).to respond_to(:verbosity)
    end

    it "#default_roots" do
      expect(config).to respond_to(:default_roots)
    end

    context "with defaults" do
      it "#git_timeout" do
        expect(config.git_timeout).to eq(300)
      end

      it "#verbosity" do
        expect(config.verbosity).to eq(Logging::NORMAL)
      end

      it "#default_roots" do
        expect(config.default_roots).to eq(%w[sites sitesUbuntu work])
      end
    end
  end
end
