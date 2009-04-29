Gem::Specification.new do |s|
	s.name     = "spomskyd"
	s.version  = "0.2.1"
	s.date     = "2009-04-29"
	s.summary  = "RubySMS application to implement the OMC SMS Proxy Protocol"
	s.email    = "amckaig@unicef.org"
	s.homepage = "http://github.com/adammck/spomskyd"
	s.authors  = ["Adam Mckaig"]
	s.has_rdoc = false
	
	s.files = [
		"lib/spomskyd.rb",
		"bin/spomskyd"
	]
	
	s.executables = [
		"spomskyd"
	]
	
	s.add_dependency("adammck-rubysms")
	s.add_dependency("mongrel")
	s.add_dependency("rack")
	s.add_dependency("uuid")
end
