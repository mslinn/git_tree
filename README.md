`git_urls`
[![Gem Version](https://badge.fury.io/rb/git_urls.svg)](https://badge.fury.io/rb/git_urls)
===========

`git_urls` scans a git directory tree and writes out a script that clones the repos in the tree, 
and adds upstream remotes as required. 
Directories containing a file called .ignore are ignored.


## Usage

```
$ gitUrls $work
```


## Installation

Type the following at a shell prompt

```ruby
gem install git_urls
```


## Additional Information
More information is available on
[Mike Slinn&rsquo;s website](https://www.mslinn.com/git/1100-git-tree.html)


## Development

After checking out the repo, run `bin/setup` to install dependencies.

You can also run `bin/console` for an interactive prompt that will allow you to experiment.


### Build and Install Locally
To build and install this gem onto your local machine, run:
```shell
$ bundle exec rake install
```

Examine the newly built gem:
```
$ gem info git_urls

*** LOCAL GEMS ***
git_urls (1.0.0)
    Author: Mike Slinn
    Homepage:
    https://github.com/mslinn/git_urls
    License: MIT
    Installed at: /home/mslinn/.gems
```


### Build and Push to RubyGems
To release a new version,
  1. Update the version number in `version.rb`.
  2. Commit all changes to git; if you don't the next step might fail with an unexplainable error message.
  3. Run the following:
     ```shell
     $ bundle exec rake release
     ```
     The above creates a git tag for the version, commits the created tag,
     and pushes the new `.gem` file to [RubyGems.org](https://rubygems.org).


## Contributing

1. Fork the project
2. Create a descriptively named feature branch
3. Add your feature
4. Submit a pull request


## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
