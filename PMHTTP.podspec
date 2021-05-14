Pod::Spec.new do |s|
  s.name         = "PMHTTP"
  s.version      = "4.5.0"
  s.summary      = "Swift/Obj-C HTTP framework with a focus on REST and JSON"

  s.description  = <<-DESC
                   PMHTTP is an HTTP framework built around NSURLSession and designed for Swift while retaining Obj-C compatibility.
                   DESC

  s.homepage     = "https://github.com/postmates/PMHTTP"
  s.license      = { :type => "MIT", :file => "LICENSE-MIT" }

  s.author             = "Lily Ballard"
  s.social_media_url   = "https://twitter.com/LilyInTech"

  s.ios.deployment_target = "8.0"
  s.osx.deployment_target = "10.10"
  s.watchos.deployment_target = "2.0"
  s.tvos.deployment_target = "9.0"

  s.swift_version = '4.2'

  s.source       = { :git => "https://github.com/postmates/PMHTTP.git", :tag => "v#{s.version}" }
  s.source_files  = "Sources"
  s.private_header_files = "Sources/PMHTTPManager*.h"

  s.framework  = "CFNetwork"
  s.library    = 'c++'
  s.module_map = "Sources/pmhttp.modulemap"

  s.dependency "PMJSON", ">= 3.0", "< 5.0"
end
