require 'thor'
require 'gitx'
require 'gitx/cli/base_command'
require 'gitx/cli/buildtag_command'

module Gitx
  module Cli
    class NukeCommand < BaseCommand
      desc 'nuke', 'nuke the specified aggregate branch and reset it to a known good state'
      method_option :destination, type: :string, aliases: '-d', desc: 'destination branch to reset to'
      def nuke(bad_branch)
        good_branch = options[:destination] || ask("What branch do you want to reset #{bad_branch} to? (default: #{bad_branch})")
        good_branch = bad_branch if good_branch.empty?

        last_known_good_tag = current_build_tag(good_branch)
        return unless yes?("Reset #{bad_branch} to #{last_known_good_tag}? (y/n)", :green)

        assert_aggregate_branch!(bad_branch)
        return if migrations_need_to_be_reverted?(bad_branch, last_known_good_tag)

        say 'Resetting '
        say "#{bad_branch} ", :green
        say 'branch to '
        say last_known_good_tag, :green

        checkout_branch config.base_branch
        run_git_cmd('branch', '--delete', '--force', bad_branch) rescue Gitx::Executor::ExecutionError
        run_git_cmd('push', 'origin', '--delete', bad_branch) rescue Gitx::Executor::ExecutionError
        run_git_cmd 'checkout', '-b', bad_branch, last_known_good_tag
        run_git_cmd 'share'
        checkout_branch config.base_branch
      end

      private

      def migrations_need_to_be_reverted?(bad_branch, last_known_good_tag)
        return false unless File.exist?('db/migrate')

        outdated_migrations = run_git_cmd('diff', "#{last_known_good_tag}...#{bad_branch}", '--name-only', 'db/migrate').split
        return false if outdated_migrations.empty?

        say "#{bad_branch} contains migrations that may need to be reverted.  Ensure any reversable migrations are reverted on affected databases before nuking.", :red
        say 'Example commands to revert outdated migrations:'
        outdated_migrations.reverse_each do |migration|
          version = File.basename(migration).split('_').first
          say "rake db:migrate:down VERSION=#{version}"
        end
        !yes?("Are you sure you want to nuke #{bad_branch}? (y/n) ", :green)
      end

      def current_build_tag(branch)
        last_build_tag = build_tags_for_branch(branch).last
        raise "No known good tag found for branch: #{branch}.  Verify tag exists via `git tag -l`" unless last_build_tag

        last_build_tag
      end

      def build_tags_for_branch(branch)
        run_git_cmd 'fetch', '--tags'
        prefix = [BuildtagCommand::BUILD_TAG_PREFIX, branch].join(BuildtagCommand::BUILD_TAG_SEPARATOR)
        tags = repo.tags.select { |t| t.name.starts_with?(prefix) }
        tags.map(&:name).sort
      end
    end
  end
end
