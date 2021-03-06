# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require "date"
require "astroboa-cli/version"

Gem::Specification.new do |s|
  s.name = "astroboa-cli"
  s.version = AstroboaCLI::VERSION
  s.platform = Gem::Platform::RUBY
  s.authors = ["Gregory Chomatas"]
  s.email = ["gchomatas@betaconcept.com"]
  s.homepage = "http://www.astroboa.org"
  s.date = Date.today.to_s
  s.summary = %q{Astroboa Command Line Interface for astroboa platform and astroboa apps management.}
  s.description = %q{astroboa-cli provides commands for installing astroboa platform, creating repositories, taking backups, deploying applications to astroboa, etc.}
  s.license = "LGPL"
  s.post_install_message = <<-MESSAGE
  *   run 'astroboa-cli help' to see the available commands
  MESSAGE

  s.rubyforge_project = "astroboa-cli"

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }

  s.require_paths = ["lib"]
  s.add_runtime_dependency 'progressbar'
  s.add_runtime_dependency 'rubyzip'
  s.add_runtime_dependency 'erubis'
  s.add_runtime_dependency 'nokogiri', '>= 1.5.5'
  s.add_runtime_dependency 'colorize'
  s.add_runtime_dependency 'zip-zip'
  s.executables = ["astroboa-cli"]
end
