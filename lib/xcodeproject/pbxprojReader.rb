#
# PbxprojReader
# Reads (parses) an Xcode project.pbxproj file.
# I'm kind of embarrassed how simple this is. Ruby Cocoa FTW!
# Created by Dan Wright 10/6/2010.
#
require 'osx/foundation'

class PbxprojReader

	def initialize(projectPath)
		@projectPath = projectPath
	end
	
	def parse!
		unless File.exists?(@projectPath)
			$stderr.puts("ERROR: file #{@projectPath} does not exist. Something has gone wrong.")
			return
		end
		data = OSX::NSData.dataWithContentsOfFile(@projectPath)
		@plist = OSX::NSPropertyListSerialization.propertyListFromData_mutabilityOption_format_errorDescription(data, 0, nil, nil)
		$stderr.puts("ERROR: unable to read project file #{@projectPath}. It may be corrupt or empty.") unless @plist
	end
	
	def value(key)
		@plist[key]
	end
	
	def objectForUUID(uuid)
		@plist['objects'][uuid]
	end

	def objectOfClass(uuid, isa)
		(@plist['objects'].include?(uuid) && objectForUUID(uuid)['isa'] == isa) ? objectForUUID(uuid) : nil
	end
	
	def project
		@plist['rootObject']
	end
	
	def objectsForClass(isa)
		return [] unless @plist && @plist.include?('objects')
		@plist['objects'].keys.find_all {|uuid| objectForUUID(uuid)['isa'] == isa }
	end
	
end

