# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'pxcbackup/version'

Gem::Specification.new do |spec|
  spec.name        = 'pxcbackup'
  spec.version     = PXCBackup::VERSION
  spec.author      = 'Robbert Klarenbeek'
  spec.email       = 'robbertkl@renbeek.nl'
  spec.summary     = 'Backup tool for Percona XtraDB Cluster'
  spec.description = spec.summary
  spec.homepage    = 'https://github.com/robbertkl/pxcbackup'
  spec.license     = 'MIT'

  spec.files       = `git ls-files -z`.split("\x0")
  spec.executables = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
end
