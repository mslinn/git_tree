require 'spec_helper'
require_relative '../../lib/commands/git_commit_all'
require 'tmpdir'
require 'fileutils'
require_relative '../../lib/util/log'

describe GitTree::CommitAllCommand do
  include Logging

  subject(:command) { described_class.new(args, options: options) }

  let(:args) { ['/fake/root'] }
  let(:mock_walker) { instance_double(GitTreeWalker, process: nil) }
  let(:options) { { walker: mock_walker } }

  before do
    allow(command).to receive(:log)
    allow(Logging).to receive(:verbosity).and_return(Logging::NORMAL)
  end

  describe '#run' do
    it 'initializes the GitTreeWalker after parsing options' do
      # This test ensures that the walker is created with the final, parsed arguments
      # and options, not the initial ones, which was a source of a previous bug.
      command = described_class.new(['-v', '-m', 'test message', '/some/dir'])
      allow(GitTreeWalker).to receive(:new).and_return(mock_walker)
      command.run
      # It should be called with the arguments left *after* option parsing.
      expect(GitTreeWalker).to have_received(:new)
        .with(['/some/dir'], options: a_hash_including(message: 'test message'))
    end

    context 'with a real git repository' do
      let(:tmpdir) { Dir.mktmpdir('git_commit_all_spec') }
      let(:repo_path) { File.join(tmpdir, 'real_repo') }
      let(:commit_message) { 'Integration test commit' }

      before do
        # Create a real git repo with an initial commit
        bare_repo_path = File.join(tmpdir, 'remote.git')
        system('git', 'init', '--bare', bare_repo_path, out: File::NULL, err: File::NULL)
        system('git', 'clone', bare_repo_path, repo_path, out: File::NULL, err: File::NULL)
        system('git', '-C', repo_path, 'config', 'user.name', 'Test User', out: File::NULL, err: File::NULL)
        system('git', '-C', repo_path, 'config', 'user.email', 'test@example.com', out: File::NULL, err: File::NULL)
        File.write(File.join(repo_path, 'README.md'), 'Initial commit')
        system('git', '-C', repo_path, 'add', '.', out: File::NULL, err: File::NULL)
        system('git', '-C', repo_path, 'commit', '-m', 'Initial commit', out: File::NULL, err: File::NULL)

        # Create a change to be committed by the command
        File.write(File.join(repo_path, 'new_file.txt'), 'This is a new file.')
      end

      after do
        FileUtils.remove_entry(tmpdir)
      end

      it 'finds the repository, commits, and pushes the changes' do
        # We run in serial mode for test predictability
        command = described_class.new([tmpdir, '-m', commit_message, '-s'])
        command.run

        # Verify that the new commit exists
        log_output = `git -C #{repo_path} log -1 --pretty=%B 2> /dev/null`.strip
        expect(log_output).to eq(commit_message)
      end
    end
  end
end
