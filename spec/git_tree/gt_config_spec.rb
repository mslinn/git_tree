require "anyway/testing"
require_relative "../spec_helper"

describe GitTree::GTConfig, type: :config do
  # include Anyway::Testing::Helpers # this is not necessary
  # See: https://github.com/palkan/anyway_config/blob/master/lib/anyway/testing.rb

  before do
    Anyway::Settings.current_environment = "test"
  end

  let(:config) { described_class.new }

  context "when the environment is not set" do
    it "raises an error" do
      Anyway::Settings.current_environment = nil
      expect { config }.to raise_error(RuntimeError, /Anyway::Settings environment/)
    end
  end

  context "when the environment is set" do
    it "does not raise an error" do
      expect { config }.not_to raise_error
    end
  end

  context "has attributes" do
    it "#git_timeout" do
      expect(config).to respond_to(:git_timeout)
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
