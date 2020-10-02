require_relative 'lib/multi_background_job/version'

Gem::Specification.new do |spec|
  spec.name          = 'multi-background-job'
  spec.version       = MultiBackgroundJob::VERSION
  spec.authors       = ['Marcos G. Zimmermann']
  spec.email         = ['mgzmaster@gmail.com']

  spec.summary       = <<~SUMMARY
    A generic swappable background-job handling.
  SUMMARY
  spec.description   = <<~DESCRIPTION
    A generic swappable background-job handling.
  DESCRIPTION

  spec.homepage      = 'https://github.com/marcosgz/multi-background-job'
  spec.license       = 'MIT'
  spec.required_ruby_version = Gem::Requirement.new('>= 2.3.0')

  raise 'RubyGems 2.0 or newer is required to protect against public gem pushes.' unless spec.respond_to?(:metadata)
  spec.metadata['homepage_uri']      = spec.homepage
  spec.metadata['bug_tracker_uri']   = 'https://github.com/marcosgz/multi-background-job/issues'
  spec.metadata['documentation_uri'] = 'https://github.com/marcosgz/multi-background-job'
  spec.metadata['source_code_uri']   = 'https://github.com/marcosgz/multi-background-job'

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files         = Dir.chdir(File.expand_path('..', __FILE__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  end

  spec.bindir        = 'exe'
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.add_dependency 'redis', '>= 0.0.0'
end
