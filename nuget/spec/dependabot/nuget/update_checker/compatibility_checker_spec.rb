# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/nuget/update_checker/compatibility_checker"
require "dependabot/nuget/update_checker/repository_finder"
require "dependabot/nuget/update_checker/tfm_finder"

RSpec.describe Dependabot::Nuget::CompatibilityChecker do
  subject(:checker) do
    described_class.new(
      dependency_urls: dependency_urls,
      dependency: dependency,
      tfm_finder: tfm_finder
    )
  end

  let(:dependency_urls) do
    Dependabot::Nuget::RepositoryFinder.new(
      dependency: dependency,
      credentials: credentials,
      config_files: []
    ).dependency_urls
  end

  let(:credentials) do
    [{
      "type" => "nuget_feed",
      "url" => "https://api.nuget.org/v3/index.json",
      "token" => "my:passw0rd"
    }]
  end

  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: dependency_version,
      requirements: dependency_requirements,
      package_manager: "nuget"
    )
  end

  let(:dependency_name) { "Microsoft.AppCenter.Crashes" }
  let(:dependency_version) { "5.0.2" }
  let(:dependency_requirements) do
    [{ file: "my.csproj", requirement: "5.0.2", groups: ["dependencies"], source: nil }]
  end

  let(:tfm_finder) do
    Dependabot::Nuget::TfmFinder.new(
      dependency_files: dependency_files,
      credentials: credentials
    )
  end

  let(:dependency_files) { [csproj] }
  let(:csproj) do
    Dependabot::DependencyFile.new(name: "my.csproj", content: csproj_body)
  end
  let(:csproj_body) do
    <<~XML
      <Project Sdk="Microsoft.NET.Sdk">
        <PropertyGroup>
          <TargetFramework>uap10.0.16299</TargetFramework>
        </PropertyGroup>
        <ItemGroup>
          <PackageReference Include="Microsoft.AppCenter.Crashes" Version="5.0.2" />
        </ItemGroup>
      </Project>
    XML
  end

  context "#compatible?" do
    subject(:compatible) { checker.compatible?(version) }

    before do
      stub_request(:get, "https://api.nuget.org/v3/registration5-gz-semver2/microsoft.appcenter.crashes/index.json")
        .to_return(
          status: 200,
          body: {
            items: [
              items: [
                {
                  catalogEntry: {
                    listed: true,
                    version: "5.0.2"
                  }
                },
                {
                  catalogEntry: {
                    listed: true,
                    version: "5.0.3"
                  }
                }
              ]
            ]
          }.to_json
        )
    end

    context "when the `.nuspec` reports itself as a development dependency, but still has regular dependencies" do
      let(:csproj_body) do
        <<~XML
          <Project Sdk="Microsoft.NET.Sdk">
            <PropertyGroup>
              <TargetFramework>net6.0</TargetFramework>
            </PropertyGroup>
            <ItemGroup>
              <PackageReference Include="Microsoft.AppCenter.Crashes" Version="5.0.2" />
            </ItemGroup>
          </Project>
        XML
      end

      before do
        nuspec502 =
          <<~XML
            <package xmlns="http://schemas.microsoft.com/packaging/2013/05/nuspec.xsd">
              <metadata>
                <id>Microsoft.AppCenter.Crashes</id>
                <version>5.0.2</version>
                <developmentDependency>true</developmentDependency>
                <dependencies>
                  <group targetFramework="net6.0">
                  </group>
                </dependencies>
              </metadata>
            </package>
          XML
        nuspec503 = nuspec502.gsub("5.0.2", "5.0.3")
        nuspec601 = nuspec502.gsub("5.0.2", "6.0.1").gsub("net6.0", "net8.0")
        stub_request(:get, "https://api.nuget.org/v3-flatcontainer/microsoft.appcenter.crashes/5.0.2/microsoft.appcenter.crashes.nuspec")
          .to_return(
            status: 200,
            body: nuspec502
          )
        stub_request(:get, "https://api.nuget.org/v3-flatcontainer/microsoft.appcenter.crashes/5.0.3/microsoft.appcenter.crashes.nuspec")
          .to_return(
            status: 200,
            body: nuspec503
          )
        stub_request(:get, "https://api.nuget.org/v3-flatcontainer/microsoft.appcenter.crashes/6.0.1/microsoft.appcenter.crashes.nuspec")
          .to_return(
            status: 200,
            body: nuspec601
          )
      end

      context "with a targetFramework compatible version" do
        let(:version) { "5.0.3" }

        it "returns the correct data" do
          expect(compatible).to be_truthy
        end
      end

      context "with a targetFramework non-compatible version" do
        let(:version) { "6.0.1" }

        it "returns the correct data" do
          expect(compatible).to be_falsey
        end
      end
    end

    context "when the `.nuspec` has groups without a `targetFramework` attribute" do
      let(:version) { "5.0.3" }

      before do
        stub_request(:get, "https://api.nuget.org/v3-flatcontainer/microsoft.appcenter.crashes/5.0.2/microsoft.appcenter.crashes.nuspec")
          .to_return(
            status: 200,
            body: fixture("nuspecs", "Microsoft.AppCenter.Crashes_faked.nuspec")
          )
        stub_request(:get, "https://api.nuget.org/v3-flatcontainer/microsoft.appcenter.crashes/5.0.3/microsoft.appcenter.crashes.nuspec")
          .to_return(
            status: 200,
            body: fixture("nuspecs", "Microsoft.AppCenter.Crashes_faked.nuspec")
          )
      end

      it "returns the correct data" do
        expect(compatible).to be_truthy
      end
    end
  end
end
