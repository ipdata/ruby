# frozen_string_literal: true

require "bundler/gem_tasks"

# In CI the release workflow already handles tags via the bump job,
# so skip Bundler's source-control tasks to avoid "tag already exists" errors.
if ENV["CI"]
  Rake::Task["release:guard_clean"].clear
  task "release:guard_clean"
  Rake::Task["release:source_control_push"].clear
  task "release:source_control_push"
end

require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList["test/**/test_*.rb"]
end

task default: :test
