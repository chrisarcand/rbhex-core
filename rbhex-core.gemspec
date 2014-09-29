# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'rbhex/core/version'

Gem::Specification.new do |spec|
  spec.name          = "rbhex-core"
  spec.version       = Rbhex::CORE_VERSION
  spec.authors       = ["Chris Arcand", "Rahul Kumar"]
  spec.email         = ["chris@chrisarcand.com"]
  spec.description   = "Ruby curses/ncurses widgets for easy application development on text terminals"
  spec.summary       = "Ruby Ncurses Toolkit core infrastructure and widgets"
  spec.homepage      = "https://github.com/ChrisArcand/rbhex-core"
  spec.license       = "The Ruby License"

  spec.files         = `git ls-files`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  if spec.respond_to? :specification_version
    spec.specification_version = 3

    if Gem::Version.new(Gem::VERSION) >= Gem::Version.new('1.2.0')
      spec.add_runtime_dependency(%q<ffi-ncurses>, [">= 0.4.0"])
    else
      spec.add_dependency(%q<ffi-ncurses>, [">= 0.4.0"])
    end
  else
    spec.add_dependency(%q<ffi-ncurses>, [">= 0.4.0"])
  end
end
