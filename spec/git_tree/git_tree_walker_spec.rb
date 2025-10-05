require 'spec_helper'
require 'tmpdir'
require 'fileutils'
require_relative '../../lib/util/git_tree_walker'

describe GitTreeWalker do
  # This spec tests the actual file system walking logic of GitTreeWalker.
  # It creates a temporary directory structure with fake git repos to ensure
  # that repositories are found correctly and that .ignore files are respected.

  let(:tmpdir) { Dir.mktmpdir('git_tree_walker_spec') }
  let(:work_dir) { File.join(tmpdir, 'work') }
  let(:sites_dir) { File.join(tmpdir, 'sites') }

  # Paths to the fake git repositories
  let(:repo_a_path) { File.join(work_dir, 'project_a') }
  let(:repo_b_path) { File.join(work_dir, 'project_b') }
  let(:repo_c_path) { File.join(work_dir, 'ignored_dir', 'project_c') } # This one should be ignored
  let(:repo_d_path) { File.join(sites_dir, 'site_d') }

  before do
    # Create a directory structure for testing
    # /tmp/spec-XXXX/
    #   - work/
    #     - project_a/.git
    #     - project_b/.git
    #     - ignored_dir/
    #       - .ignore
    #       - project_c/.git  <- Should be skipped
    #   - sites/
    #     - site_d/.git

    [repo_a_path, repo_b_path, repo_c_path, repo_d_path].each do |repo_path|
      FileUtils.mkdir_p(File.join(repo_path, '.git'))
    end

    # Create an ignore file
    FileUtils.touch(File.join(work_dir, 'ignored_dir', '.ignore'))
  end

  after do
    FileUtils.remove_entry(tmpdir)
  end

  describe '#find_and_process_repos' do
    it 'finds all git repositories and respects .ignore files' do
      walker = described_class.new([work_dir, sites_dir])
      found_repos = []

      walker.find_and_process_repos do |dir, _root_arg|
        found_repos << dir
      end

      expect(found_repos).to contain_exactly(repo_a_path, repo_b_path, repo_d_path)
      expect(found_repos).not_to include(repo_c_path)
    end
  end
end
