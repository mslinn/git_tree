require_relative '../lib/replicate_git_tree'

RSpec.describe('Replicate Git Tree') do
  it 'finds git repos under a normal directory' do
    dirs = ReplicateGitTree.directories_to_process 'demo'
    expect(dirs).to eq(
      [
        'proj_a/',
        'proj_b/',
        'sub1/proj_d/',
        'sub1/proj_e/',
        'sub1/proj_f/'
      ]
    )
  end

  it 'finds git repos under a symlinked directory' do
    base = ReplicateGitTree.expand_env '$work'
    dirs = ReplicateGitTree.directories_to_process base
    expect(dirs).to eq(
      [
      ]
    )
  end
end
