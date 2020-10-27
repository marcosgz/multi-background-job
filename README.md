# MultiBackgroundJob

This library provices an centralized interface to push jobs to a variety of queuing backends. Thus allowing to send jobs to multiple external services. If you are running a [Ruby on Rails](https://github.com/rails/rails) application consider using [Active Jobs](https://github.com/rails/rails/tree/master/activejob). ActiveJobs integrates with a wider range of services and builtin support.

Supported Services:
* Faktory
* Sidekiq

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'multi-background-job'
```

And then execute:

    $ bundle install

Or install it yourself as:

    $ gem install multi-background-job

## Usage

This gem should work with default configurations if you have `REDIS_URL` and/or `FAKTORY_URL` environment variables correctly defined. But you can use the `MultiBackgroundJob#configure` method to custumize default settings.


```ruby
MultiBackgroundJob.configure do |config|
  config.config_path = 'config/background_jobs.yml' # You can use an YAML file. (Default to nil)
  config.redis_pool_size = 10                       # Connection Pool size for redis. (Default to 5)
  config.redis_pool_timeout = 10                    # Connection Pool timeouf for redis. (Default to 5)
  config.redis_namespace = 'app-name'               # The prefix of redis storage keys. (Default to multi-bg)
  config.redis_config = { path: "/tmp/redis.sock" } # List of configurations to be passed along to the Redis.new. (Default to {})
  config.workers = {                                # List of workers and its configurations. (Default to {})
    'Accounts::ConfirmationEmailWorker' => { retry: 5, queue: 'mailing' },
  }
  config.strict = false                             # Only allow to push jobs to known workers. See `config.workers`. (Default to true)
end
```

### Unique Jobs

This library provides one experimental technology to avoid enqueue duplicated jobs. Pro versions of sidekiq and faktory provides this functionality. But this project exposes a mechanism to make this control using `Redis`. It's not required by default. You can load this function by require and initialize the `UniqueJob` middleware according to the service(`:faktory` or `:sidekiq`).

```ruby
require 'multi_background_job/middleware/unique_job'
MultiBackgroundJob::Middleware::UniqueJob::bootstrap(service: :sidekiq)
# Or
MultiBackgroundJob::Middleware::UniqueJob::bootstrap(service: :faktory)
```

After that just define the `:uniq` settings by worker

```ruby
MultiBackgroundJob['Mailing::SignUpWorker', uniq: { across: :queue, timeout: 120 }]
  .with_args('User', 1)
  .push(to: :sidekiq)
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/marcosgz/multi-background-job.


## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
