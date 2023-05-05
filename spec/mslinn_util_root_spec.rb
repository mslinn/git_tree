require_relative '../lib/evar'

RSpec.describe(MslinnUtil) do
  it 'finds level 1 root for one path with many slashes' do
    strings = [
      '/root/sub3/sub1'
    ]
    actual = described_class.roots(strings, 1)
    expect(actual).to eq ['/root/sub3']
  end

  it 'finds level 1 root for one path with 1 slash' do
    strings = [
      '/root'
    ]
    actual = described_class.roots(strings, 1)
    expect(actual).to eq []

    actual = described_class.roots(strings, 1, allow_root_match: true)
    expect(actual).to eq ['/']
  end

  it 'finds roots for two paths' do
    strings = [
      '/root/sub1/sub2/blah',
      '/root/sub3/sub1'
    ]
    actual = described_class.roots(strings, 1)
    expect(actual).to eq ['/root']
  end

  it 'finds level 1 root for multiple paths' do
    strings = [
      '/root/sub1/sub2/blah',
      '/root/sub1/sub2',
      '/root/sub1',
      '/root/sub3/sub1'
    ]
    actual = described_class.roots(strings, 1)
    expect(actual).to eq ['/root']
  end
end
