Pod::Spec.new do |s|

  s.name = 'Sundial'
  s.version = '5.1.22'
  s.summary = 'Collection view layout for pager header'

  s.homepage = 'https://github.com/Katterpillar/Sundial'
  s.license = { :type => "MIT" }
  s.author = {
    'Sergei Mikhan' => 'sergei@netcosports.com'
  }
  s.source = { :git => 'https://github.com/Katterpillar/Sundial', :branch => 'master' }

  s.ios.deployment_target = '13.0'
  s.dependency 'Astrolabe/Core'
  s.swift_versions = ['5.0', '5.1']
  s.source_files = ['Sources/**/*.swift']

end
