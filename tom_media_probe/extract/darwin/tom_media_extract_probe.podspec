Pod::Spec.new do |s|
  s.name             = 'tom_media_extract_probe'
  s.version          = '0.0.1'
  s.summary          = 'Audio and still frames out of a video, over AVFoundation.'
  s.description      = 'The extraction half of tom_media_probe. A probe, not a product.'
  s.homepage         = 'https://github.com/al-the-bear/tom_modules'
  s.license          = { :type => 'BSD-3-Clause', :file => '../LICENSE' }
  s.author           = { 'Tom' => 'noreply@example.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'tom_media_extract_probe/Sources/tom_media_extract_probe/**/*.swift'
  s.ios.dependency 'Flutter'
  s.osx.dependency 'FlutterMacOS'
  s.ios.deployment_target = '13.0'
  s.osx.deployment_target = '10.15'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end
