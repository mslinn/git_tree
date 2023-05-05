require_relative '../lib/evar'

RSpec.describe(MslinnUtil) do
  it 'finds common prefix' do
    strings = [
      '/root/sub1/sub2/blah',
      '/root/sub1/sub2',
      '/root/sub1',
      '/root/sub3/sub1'
    ]
    actual = described_class.common_prefix strings
    expect(actual).to eq '/root'
  end

  it 'finds common prefix with 2 roots' do
    strings = [
      '/root/sub1/sub2/blah',
      '/root/sub1/sub2',
      '/root/sub1',
      '/root2/sub3/sub1'
    ]
    actual = described_class.common_prefix strings
    expect(actual).to eq ''

    actual = described_class.common_prefix(strings, allow_root_match: true)
    expect(actual).to eq '/'
  end
end
