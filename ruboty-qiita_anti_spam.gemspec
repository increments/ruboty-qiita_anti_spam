# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'ruboty/qiita_anti_spam/version'

Gem::Specification.new do |spec|
  spec.name          = "ruboty-qiita_anti_spam"
  spec.version       = Ruboty::QiitaAntiSpam::VERSION
  spec.authors       = ["Tomoki Aonuma"]
  spec.email         = ["uasi@uasi.jp"]

  spec.summary       = %q{Ruboty plug-in for Qiita's internal anti-spam system.}
  spec.description   = %q{Ruboty plug-in for Qiita's internal anti-spam system.}
  spec.homepage      = "https://github.com/increments/ruboty-qiita_anti_spam"

  spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.10"
  spec.add_development_dependency "rake", "~> 10.0"

  spec.add_runtime_dependency "activesupport"
  spec.add_runtime_dependency "akismet"
  spec.add_runtime_dependency "google-api-client", "~> 0.9.pre1"
  spec.add_runtime_dependency "qiita"
  spec.add_runtime_dependency "ruboty"
end
