# See https://github.com/palkan/anyway_config?tab=readme-ov-file#test-helpers
describe GitTree::GTConfig, type: :config do
  gt_subjectsubject { described_class.new }

  specify do
    # Ensure that the env vars are set to the specified
    # values within the block and reset to the previous values
    # outside of it.
    with_env(
      "HEROKU_APP_NAME"        => "kin-web-staging",
      "HEROKU_APP_ID"          => "abc123",
      "HEROKU_DYNO_ID"         => "ddyy",
      "HEROKU_RELEASE_VERSION" => "v0",
      "HEROKU_SLUG_COMMIT"     => "3e4d5a"
    ) do
      expect(gt_subject).to have_attributes(
        app_name:        "kin-web-staging",
        app_id:          "abc123",
        dyno_id:         "ddyy",
        release_version: "v0",
        slug_commit:     "3e4d5a"
      )
    end
  end
end
