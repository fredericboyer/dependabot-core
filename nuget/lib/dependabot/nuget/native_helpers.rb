# typed: strong
# frozen_string_literal: true

require "shellwords"
require "sorbet-runtime"

require_relative "nuget_config_credential_helpers"

module Dependabot
  module Nuget
    module NativeHelpers
      extend T::Sig

      sig { returns(String) }
      def self.native_helpers_root
        helpers_root = ENV.fetch("DEPENDABOT_NATIVE_HELPERS_PATH", nil)
        return File.join(helpers_root, "nuget") unless helpers_root.nil?

        File.expand_path("../../../helpers", __dir__)
      end

      sig { params(project_tfms: T::Array[String], package_tfms: T::Array[String]).returns(T::Boolean) }
      def self.run_nuget_framework_check(project_tfms, package_tfms)
        exe_path = File.join(native_helpers_root, "NuGetUpdater", "NuGetUpdater.Cli")
        command_parts = [
          exe_path,
          "framework-check",
          "--project-tfms",
          *project_tfms,
          "--package-tfms",
          *package_tfms,
          "--verbose"
        ]
        command = Shellwords.join(command_parts)

        fingerprint = [
          exe_path,
          "framework-check",
          "--project-tfms",
          "<project-tfms>",
          "--package-tfms",
          "<package-tfms>",
          "--verbose"
        ].join(" ")

        puts "running NuGet updater:\n" + command

        output = SharedHelpers.run_shell_command(command, fingerprint: fingerprint)
        puts output

        # Exit code == 0 means that all project frameworks are compatible
        true
      rescue Dependabot::SharedHelpers::HelperSubprocessFailed
        # Exit code != 0 means that not all project frameworks are compatible
        false
      end

      # rubocop:disable Metrics/MethodLength
      sig do
        params(
          repo_root: String,
          proj_path: String,
          dependency: Dependency,
          is_transitive: T::Boolean,
          credentials: T::Array[T.untyped]
        ).void
      end
      def self.run_nuget_updater_tool(repo_root:, proj_path:, dependency:, is_transitive:, credentials:)
        exe_path = File.join(native_helpers_root, "NuGetUpdater", "NuGetUpdater.Cli")
        command_parts = [
          exe_path,
          "update",
          "--repo-root",
          repo_root,
          "--solution-or-project",
          proj_path,
          "--dependency",
          dependency.name,
          "--new-version",
          dependency.version,
          "--previous-version",
          dependency.previous_version,
          is_transitive ? "--transitive" : nil,
          "--verbose"
        ].compact

        command = Shellwords.join(command_parts)

        fingerprint = [
          exe_path,
          "update",
          "--repo-root",
          "<repo-root>",
          "--solution-or-project",
          "<path-to-solution-or-project>",
          "--dependency",
          "<dependency-name>",
          "--new-version",
          "<new-version>",
          "--previous-version",
          "<previous-version>",
          is_transitive ? "--transitive" : nil,
          "--verbose"
        ].compact.join(" ")

        puts "running NuGet updater:\n" + command

        NuGetConfigCredentialHelpers.patch_nuget_config_for_action(credentials) do
          output = SharedHelpers.run_shell_command(command, fingerprint: fingerprint)
          puts output
        end
      end
      # rubocop:enable Metrics/MethodLength
    end
  end
end
