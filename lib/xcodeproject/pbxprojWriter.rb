# pbxprojWriter.rb
# A library for creating Xcode project.pbxproj files
# Version 1.2
# Copyright (c) Dan Wright 2011-2012, All rights reserved.
# http://danwright.info

require 'FileUtils'
require 'xcodeproject/uuid.rb'

# method name conventions:
#   First word of method describes behavior as follows:
#       "new--" creates a new object of the specified type and returns the uuid
#       "find--" finds an existing object of the specified type, returning its uuid or nil if the object doesn't exist
#       "get--" is a simple getter (without side effects such as creating an object)

class PbxprojWriter
    
	def initialize
        # ('p' is short for 'project data')
		@p = {'archiveVersion' => 1,
			 'classes' => {}, 
			 'objectVersion' => 42, 
             'objects' => {}}
        
        @DEFAULT_DEVELOPMENT_LANGUAGE = 'en'
        @COMPATIBILITY_VERSION = 'Xcode 3.2'
        
		@productRefGroup = nil
		@uuid_ = UUID.new
		@isFinished_ = false
        
        # Mapping from file extensions to Xcode file types (UTIs)
        # Use 'addFileTypes' to add more mappings.
		@fileTypesMap_ = {
            '.a' => 'archive.ar',
            '.aif' => 'public.aifc-audio',
            '.app' => 'wrapper.application',
            '.c' => 'sourecode.c', 
            '.cp' => 'sourcecode.cpp.cpp', '.cpp' => 'sourcecode.cpp.cpp',
            '.dylib' => 'compiled.mach-o.dylib',
            '.entitlements' => 'text.xml',
            '.framework' => 'wrapper.framework',
            '.gif' => 'image.gif',
            '.h' => 'sourcecode.c.h', 
            '.html' => 'text/html',
            '.icns' => 'image.icns',
            '.jpg' => 'image.jpeg', '.jpeg' => 'image.jpeg',
            '.m' => 'sourcecode.c.objc',
            '.md' => 'source.markdown',
            '.mm' => 'sourcecode.cpp.objcpp',
            '.nib' => 'wrapper.nib',
            '.pch' => 'sourcecode.c.h',
            '.pdf' => 'image.pdf',
            '.php' => 'text.script.php',
            '.plist' => 'text.plist.xml',
            '.png' => 'image.png', '.PNG' => 'image.png',
            '.py' => 'text.script.python',
            '.rb' => 'text.script.ruby',
            '.rtf' => 'text.rtf',
            '.sh' => 'text.script.sh',
            '.storyboard' => 'file',
            '.strings' => 'text.plist.strings',
            '.tiff' => 'image.tiff', '.tif' => 'image.tiff',
            '.txt' => 'text',
            '.xcconfig' => 'text.xcconfig',
            '.xib' => 'file.xib',
            '' => 'file'
        }
        
        @DEFAULT_CONFIGURATIONS = ['Debug', 'Release']
        @configurations_ = @DEFAULT_CONFIGURATIONS
        
        @PROXYTYPE_TARGET = 1
        @PROXYTYPE_PRODUCT = 2
        
        @SRCTREE_BUILT_PRODUCTS = 'BUILT_PRODUCTS_DIR'
        @SRCTREE_SDK = 'SDKROOT'
        @SRCTREE_ABSOLUTE = '<absolute>'
        @SRCTREE_GROUP = '<group>'
        
        # The meanings of SOURCE_ROOT and PROJECT_ROOT are commonly reversed
        # when we placed the project file outside of the source tree.
        
        # SOURCE_ROOT is the directory that contains the generated .xcodeproj.
        @SRCTREE_SOURCEROOT = 'SOURCE_ROOT'
        # PROJECT_ROOT is the directory of the "root group" of the project.
        # This is *usually* set to be the root directory of the source tree.
        @SRCTREE_PROJECTROOT = 'PROJECT_ROOT'

        @SRCTREE_PROJECT = @SRCTREE_SOURCEROOT
    end

	# If you use Qt, you'll probably want to add these types:
    #'.pro' => 'text', '.pri' => 'text',
    #'.qrc' => 'text', # custom for Qt
    #'.ui' => 'text.xml', # custom for Qt
    def addFileTypes(mapExtensionToFileType = {})
        @fileTypesMap_.merge!(mapExtensionToFileType)
    end
    
    def getFileTypeForFile(path)
		ext = File.extname(path)
		$stderr.puts("*** WARNING: do not recognize file type for '#{ext}', it may be added with addFileTypes (file #{path})") if !@fileTypesMap_.include?(ext)
		@fileTypesMap_[ext] || 'file'
	end
	
	def writeArray(fp, arr, indent)
		arr.each { |element|
            if element.instance_of?(String)
                if element.match("[\s,\$;})+{(<>@]") || element == ""
                    element = '"' + element + '"'
                end
            end
			fp.puts("#{indent}#{element},")
		}
	end
	
	def writeRecord(fp, record, indent)
		$include_comments = true
		
		# sort keys alphabetically
		sortedKeys = record.keys.sort
		# .. but then move 'isa' in front
		if record.include?('isa')
			sortedKeys.delete('isa')
			sortedKeys.unshift('isa')
		elsif sortedKeys.count > 0 && record[sortedKeys[0]].instance_of?(Hash) && record[sortedKeys[0]].include?('isa')
			sortedKeys = record.keys.sort {|a,b|
                record[a]['isa'] <=> record[b]['isa']
            }
		end
		
		# remove comment
		sortedKeys.delete('comment')
		
		sortedKeys.each { |key|
			if (record[key].instance_of?(Array))
				fp.puts("#{indent}#{key} = (")
				writeArray(fp, record[key], "#{indent}\t")
				fp.puts("#{indent});")
			elsif record[key].instance_of?(Hash)
				comment = record[key].include?('comment') && $include_comments ? " /* #{record[key]['comment']} */" : ""
				fp.puts("#{indent}#{key}#{comment} = {")
				writeRecord(fp, record[key], "#{indent}\t")
				fp.puts("#{indent}};")
			elsif record[key].instance_of?(String)
                record[key].gsub!("\n", "\\n")
				if record[key].include?('"')
                    value = record[key].gsub('"', '\\' + '"')
					fp.puts("#{indent}#{key} = \"#{value}\";")
                elsif record[key].include?("'") || record[key].match('[-\s,\$;})+{(<>@]') || record[key] == ""
                    fp.puts("#{indent}#{key} = \"#{record[key]}\";")
				else
					fp.puts("#{indent}#{key} = #{record[key]};")
				end
			else
				fp.puts("#{indent}#{key} = #{record[key]};")
			end
		}
	end
	
	def write(path)
		finish
		if path
			begin
				FileUtils.mkdir_p(path)
			rescue
			end
			fp = File.new("#{path}/project.pbxproj", "w")
		else
			fp = $stderr
		end
		fp.puts("// !$*UTF8*$!")
		fp.puts("{")
		writeRecord(fp, @p, "\t")
		fp.puts("}")
		fp.close unless fp == $stderr
	end
	
	def uuidGen
		@uuid_.generate
		@uuid_.to_s
	end
	
	def isID?(uuidMaybe)
		@uuid_.isValid?(uuidMaybe)
	end
	
    def newObject(className, properties = {})
        throw :bad_className unless className.class == String
        uuid = uuidGen
        @p['objects'][uuid] = {'isa' => className}.merge(properties)
        uuid
    end
        
    def isObject?(uuid)
        @p['objects'].include?(uuid)
    end
            
    def getObjectProperty(uuid, property)
        throw :invalidObject unless isObject?(uuid)
        @p['objects'][uuid][property]
    end
            
    def setObjectProperty(uuid, property, newValue)
        throw :invalidObject unless isObject?(uuid)
        @p['objects'][uuid][property] = newValue
    end
     
    def objectHasProperty?(uuid, property)
        throw :invalidObject unless isObject?(uuid)
        @p['objects'][uuid].include?(property)
    end
	
	def findAllObjectsForClass(className)
		@p['objects'].find_all { |uuid,obj| obj['isa'] == className }
	end
	
	def findAllObjectsForClassAndName(className, name)
		@p['objects'].find_all { |uuid,obj| obj['isa'] == className && obj.include?('name') && obj['name'] == name }
	end
	
	def strip_ext(path)
		base = File.basename(path)
		ext  = File.extname(base)
		ext.length == 0 ? base : base[0 .. (base.length-ext.length-1)]
	end
	
	def newBuildConfiguration(name, settings)
        newObject('XCBuildConfiguration', {'name' => name, 'buildSettings' => settings, 'comment' => name})
	end
	
    def configurations
        @configurations_
    end
    
    def debugConfiguration
        @configurations_.include?('Debug') ? 'Debug' : @configurations_.first
    end
    
    def releaseConfiguration
        @configurations_.include?('Release') ? 'Release' : @configurations_.last
    end
    
	def newStandardBuildConfiguration(name)
		newBuildConfiguration(name, {
			'ARCHS' => "$(ARCHS_STANDARD_32_64_BIT)",
			'GCC_C_LANGUAGE_STANDARD' => 'gnu99',
			'COPY_PHASE_STRIP' => (name == self.debugConfiguration) ? 'NO' : 'YES',
			'SDKROOT' => 'macosx'
			})
	end
	
	def newProductBuildConfiguration(name, productName)
		newBuildConfiguration(name, {
			'COPY_PHASE_STRIP' => (name == self.debugConfiguration) ? 'NO' : 'YES',
			'PRODUCT_NAME' => self.strip_ext(productName)
			})
	end
	
    def newStandardProjectBuildConfigurationList(projectRoot)
        buildConfigurations = []
        self.configurations.each { |configuration|
            uuid = newStandardBuildConfiguration(configuration)
            getObjectProperty(uuid, 'buildSettings')['PROJECT_ROOT'] = projectRoot if projectRoot
            buildConfigurations.push(uuid)
        }
        newObject('XCConfigurationList', {
                  'defaultConfigurationIsVisible' => 0,
                  'defaultConfigurationName' => self.releaseConfiguration,
                  'buildConfigurations' => buildConfigurations,
                  'comment' => 'project configuration'
                  })
	end
	
	def newProductBuildConfigurationList(productName)
        buildConfigurations = []
        self.configurations.each { |configuration|
            uuid = newProductBuildConfiguration(configuration, productName)
            buildConfigurations.push(uuid)
        }
        
        newObject('XCConfigurationList', {
                  'defaultConfigurationIsVisible' => 0,
                  'defaultConfigurationName' => self.releaseConfiguration,
                  'buildConfigurations' => buildConfigurations,
                  'comment' => "for target #{productName}"
                  })
    end
	
	def setKeyValueInBuildConfigurationList(buildConfigurationList, key, value)
		@p['objects'][buildConfigurationList]['buildConfigurations'].each {|bc|
            @p['objects'][bc]['buildSettings'][key] = value
		}
	end
	
	def newGroupExplicit(name, parentGroup, path=nil, sourceTree=nil)
        uuid = newObject('PBXGroup', {
                          'children' => [],
                          'sourceTree' => sourceTree ? sourceTree : (path && path.start_with?('/') ? '<absolute>' : '<group>')
                          })
        setObjectProperty(uuid, 'name', name) if name
        setObjectProperty(uuid, 'path', path) if path
        setObjectProperty(uuid, 'comment', name ? name : (path ? File.basename(path) : 'main project group'))
            
        addToGroup(uuid, parentGroup) if parentGroup
        uuid
	end
	
	# newGroup
	# specify a top-level group as "Foo"
	# specify a subgroup of "Foo" as "Foo:Bar"
	# etc. Intermediate groups that do not exist will get created automatically, however they will not get paths assigned automatically.
	def newGroup(nameSpec, path=nil, sourceTree=nil)
		$stderr.puts("*** ERROR: No group name specified") if !nameSpec || nameSpec.length == 0
		groupParts = nameSpec.split(':')
		parentGroup = self.rootGroup
		while groupParts.count > 1
			nextGroup = groupParts.shift
            matchingChildren = getObjectProperty(parentGroup, 'children').find_all {|child| getObjectProperty(child, 'name') == nextGroup}
			$stderr.puts("*** ERROR: Multiple sibling groups with the name '#{nextGroup}' [nameSpec=#{nameSpec}]") if matchingChildren.count >= 2
			parentGroup = matchingChildren.count == 0 ? newGroupExplicit(nextGroup, parentGroup, nil, nil) : matchingChildren[0]
		end
		newGroupExplicit(groupParts.shift, parentGroup, path, sourceTree)
	end
	
	def findGroupByNamePath(groupNamePath)
		$stderr.puts("*** ERROR: findGroupByNamePath not passed a string (#{groupNamePath})") if !groupNamePath.instance_of?(String)
		groupParts = groupNamePath.split(':')
		parent = self.rootGroup
		groupParts.each { |groupName|
			matchingChildren = getObjectProperty(parent, 'children').find_all {|child| getObjectProperty(child, 'name') == groupName}
			return nil if matchingChildren.count == 0
			$stderr.puts("*** ERROR: Multiple sibling groups with the name '#{groupName}' [groupNamePath=#{groupNamePath}]") if matchingChildren.count >= 2
            throw :MultipleSiblingGroups if matchingChildren.count >= 2
			parent = matchingChildren[0]
		}
		parent
	end
		
	# addToGroup
	# uuidThing is uuid of a fileRef or group; targetGroup is usually the uuid of the group, but can be a group name path spec.
	def addToGroup(uuidThing, targetGroup)
		uuidTargetGroup = isID?(targetGroup) ? targetGroup : findGroupByNamePath(targetGroup)
		uuidTargetGroup = newGroup(targetGroup) unless uuidTargetGroup
		$stderr.puts("*** ERROR: Did not find group '#{targetGroup}'") unless uuidTargetGroup
		targetGroupObject = @p['objects'][uuidTargetGroup]
        $stderr.puts("*** ERROR: Object #{targetGroup}/#{uuidTargetGroup} is not a PBXGroup (isa #{targetGroupObject['isa']})") unless targetGroupObject['isa'] == 'PBXGroup'
        throw :no_such_group unless targetGroupObject && targetGroupObject['isa'] == 'PBXGroup'
        throw :group_is_childless unless targetGroupObject.include?('children')
		targetGroupObject['children'].push(uuidThing)
	end
	
	def newProductFileReference(explicitFileType, path, sourceTree=nil)
        uuid = newObject('PBXFileReference', {
                  'explicitFileType' => explicitFileType,
                  'includeInIndex' => 0,
                  'path' => path,
                  'sourceTree' => sourceTree ? sourceTree : 'BUILT_PRODUCTS_DIR',
                  'comment' => File.basename(path)
                  })
        setObjectProperty(uuid, 'name', File.basename(path)) if File.basename(path) != path
        addToGroup(uuid, @productRefGroup)
        uuid
	end
	
	def newFileReference(path, fileType, sourceTree=nil)
        if !sourceTree && path.start_with?('/System/Library/Frameworks/')
            sourceTree = 'SDKROOT'
            path = path[1..path.length]
        end
        uuid = newObject('PBXFileReference', {
                         'lastKnownFileType' => fileType,
                         'path' => path,
                         'sourceTree' => sourceTree ? sourceTree : (path.start_with?('/') ? '<absolute>' : '<group>'),
                         'comment' => File.basename(path)
                         })
        setObjectProperty(uuid, 'name', File.basename(path)) if File.basename(path) != path
        uuid
    end
	
    def findFileReference(path)
        if File.basename(path) != path
            name = File.basename(path)
            matches = findAllObjectsForClassAndName('PBXFileReference', name)
            matches.each { |uuid,obj|
                return uuid if getObjectProperty(uuid, 'path') == path
            }
            # Fall-through in case path is for a localized resource
        end
        matches = findAllObjectsForClass('PBXFileReference')
        matches.each { |uuid,obj|
            return uuid if getObjectProperty(uuid, 'path') == path
        }
        nil
    end
    
	# setFileReferenceUsesTabs is used to change the 'uses tabs' (vs spaces)
	# flag on an individual flag. If unset, files will use the Xcode default setting.
	# We also automatically set the useTabs for Ruby and generic text files.
	def setFileReferenceUsesTabs(fileRefUuid, usesTabs)
        setObjectProperty(fileRefUuid, 'usesTabs', usesTabs)
	end
	
    def textEncodingForName(textEncodingName)
        case textEncodingName.downcase
        # We assume everything else is utf-8.
        when 'utf16', 'utf-16'
            return 10
        else
            throw :unknown_textEncodingName
        end
    end
    
    def setFileReferenceTextEncoding(fileRefUuid, textEncoding)
        setObjectProperty(fileRefUuid, 'fileEncoding', textEncoding)
    end
    
	def newUsrLib(name, targets = [])
		groupNamePath = targets.count > 0 ? "Frameworks:Linked" : "Frameworks:Other"
		group = findGroupByNamePath(groupNamePath)
		group = newGroup(groupNamePath) if group == nil
		newSourceFile("usr/lib/#{name}", group, targets, 'SDKROOT', 'PBXFrameworksBuildPhase')
	end

	def findBuildPhaseForTarget(buildPhaseClass, target)
		return nil unless @p['objects'].include?(target)
		targetNode = @p['objects'][target]
		targetBuildPhases = targetNode['buildPhases']
		buildPhase = targetBuildPhases.find {|bp| @p['objects'][bp]['isa'] == buildPhaseClass }
	end
	
    def newBuildPhaseForTarget(buildPhaseClass, target)
        targetNode = @p['objects'][target]
        buildPhase = newObject(buildPhaseClass, {
                               'buildActionMask' => 0x7FFFFFFF, #MAGIC
                               'files' => [],
                               'runOnlyForDeploymentProcessing' => 0,
                               'comment' => "#{targetNode['name']} #{buildPhaseClass}"
                               })
        targetNode['buildPhases'].push(buildPhase)
        buildPhase
    end
    
    # get the existing build phase, creating a new one if it doesn't exist yet
	def ensureBuildPhaseForTarget(buildPhaseClass, target)
        findBuildPhaseForTarget(buildPhaseClass, target) || newBuildPhaseForTarget(buildPhaseClass, target)
	end
	
    def newShellScriptBuildPhase(name, target, shellScript, options = {})
        throw :OBSOLETE_PARAMETER_TYPE unless options.is_a?(Hash)
        settings = {
            'shellPath' => '/bin/sh',
            'showEnvVarsInLog' => 0,
            'runOnlyForDeploymentPostprocessing' => 0,
            'inputPaths' => [],
            'outputPaths' => [],
            'files' => [],
            'buildActionMask' => 0x7FFFFFFF
        }
        settings.merge!(options)
        buildPhase = newObject('PBXShellScriptBuildPhase', settings.merge({'name' => name, 'shellScript' => shellScript}))
        @p['objects'][target]['buildPhases'].push(buildPhase)
        buildPhase
    end
        
    def newCopyFrameworksBuildPhase(target, options = {})
        settings = {
            'buildActionMask' => 0x7FFFFFFF,
            'dstPath' => "",
            'dstSubfolderSpec' => 10, # frameworks?
            'files' => [],
            'runOnlyForDeploymentPostprocessing' => 0
        }
        settings.merge!(options)
        buildPhase = newObject('PBXCopyFilesBuildPhase', settings)
        @p['objects'][target]['buildPhases'].push(buildPhase)        
        buildPhase
    end
    
    def newBuildFile(fileRef, target, options = {})
        properties = {
            'fileRef' => fileRef,
            'buildPhase' => 'PBXSourcesBuildPhase'
        }
        #settings = {COMPILER_FLAGS = "-fno-objc-arc"; };
        properties.merge!(options)
        # buildPhase is for our own use; unrecognized properties will go into the PBXBuildFile
        buildPhase = properties['buildPhase']
        properties.delete('buildPhase')
        uuidBuildFile = newObject('PBXBuildFile', properties)
        uuidBuildPhase = ensureBuildPhaseForTarget(buildPhase, target)
        @p['objects'][uuidBuildPhase]['files'].push(uuidBuildFile)
        uuidBuildFile
    end
    
	def newSourceFile(path, group, targets = [], sourceTree = nil, buildPhase = 'PBXSourcesBuildPhase', settings = {})
		fileRef = newFileReference(path, getFileTypeForFile(path), sourceTree)
		addToGroup(fileRef, group)
		if targets
            targets.each { |target|
                # create PBXBuildFile
                options = {'buildPhase' => buildPhase, 'comment' => File.basename(path)}
                options['settings'] = settings unless settings.empty?
                newBuildFile(fileRef, target, options)
			}
		end
		fileRef
	end
	
    def newFolderReference(path, group, targets = [], sourceTree = nil, buildPhase = 'PBXSourcesBuildPhase', settings = {})
        folderRef = newFileReference(path, 'folder', sourceTree)
        addToGroup(folderRef, group)
        folderRef
    end
    
	# A built resource file is any kind of resource (including an application) that is built by some
	# other target or project (the distinction is that it is NOT a fixed file, and may or may not exist
	# when this project is opened in Xcode). Regular resource files are added using newSourceFile
	# (with buildPhase = 'PBXResourcesBuildPhase').
	def newBuiltResourceFile(name, group, targets=[], buildPhase = 'PBXResourcesBuildPhase')
		fileRef = newProductFileReference(getFileTypeForFile(name), name)
		addToGroup(fileRef, group)
		if targets
            targets.each { |target|
                # create PBXBuildFile
                uuidBuildFile = newObject('PBXBuildFile', {'fileRef' => fileRef, 'comment' => File.basename(name)})
				uuidBuildPhase = ensureBuildPhaseForTarget(buildPhase, target)
				@p['objects'][uuidBuildPhase]['files'].push(uuidBuildFile)
			}
		end
		fileRef
	end
	
    def newBuiltSourceFile(name, group, targets=[], sourceTree=nil, buildPhase = 'PBXSourcesBuildPhase', settings = {})
        fileRef = newProductFileReference(getFileTypeForFile(name), name, sourceTree)
        addToGroup(fileRef, group)
        if targets
            targets.each { |target|
                # create PBXBuildFile
                options = settings
                options['fileRef'] = fileRef
                options['comment'] = File.basename(name)
                uuidBuildFile = newObject('PBXBuildFile', options)
                uuidBuildPhase = ensureBuildPhaseForTarget(buildPhase, target)
                @p['objects'][uuidBuildPhase]['files'].push(uuidBuildFile)
            }
        end
        fileRef
    end
    
	def newFramework(name, targets = [])
		groupNamePath = targets.count > 0 ? "Frameworks:Linked" : "Frameworks:Other"
		group = findGroupByNamePath(groupNamePath)
		group = newGroup(groupNamePath) unless group != nil
		name = "/System/Library/Frameworks/#{name}" unless name.start_with?('/')
		newSourceFile(name, group, targets, nil, 'PBXFrameworksBuildPhase')
	end
	
    def addFrameworkToCopyPhase(name, fileRef, target)
        throw :invalidObject unless isObject?(fileRef)
        uuidBuildPhase = findBuildPhaseForTarget('PBXCopyFilesBuildPhase', target)
        uuidBuildPhase = newCopyFrameworksBuildPhase(target) unless uuidBuildPhase
        uuidBuildFile = newObject('PBXBuildFile', {'fileRef' => fileRef, 'comment' => File.basename(name)})
        @p['objects'][uuidBuildPhase]['files'].push(uuidBuildFile)
    end
    
	# e.g. "resources/English.lproj/InfoPlist.strings"
	#      "resources/English.lproj/MainMenu.xib"
	#      "resources/French.lproj/MainMenu.xib"
	# newVariantGroup("MainMenu.xib", ["resources/English.lproj", "resources/French.lproj"])	
	def newVariantGroup(name,variantPaths)
		# children:
		#  PBXFileReference name = "English", path = "MainMenu.xib", sourceTree = "<group>"
		children = variantPaths.collect { |p| 
			basename = File.basename(p)
			ext = File.extname(p)
			variantName = basename[0..basename.length-ext.length-1]
			path = "#{p}/#{name}"
			fref = newFileReference(path, getFileTypeForFile(path), nil) 
            setObjectProperty(fref, 'name', variantName)
			fref
		}
        newObject('PBXVariantGroup', {
            'children' => children,
            'name' => name,
            # We do not want to set the path value!
            'sourceTree' => variantPaths[0].start_with?('/') ? '<absolute>' : '<group>',
            'comment' => name
            })
	end
	
	def newLocalizedResource(name, variantPaths, group, targets)
		variantGroup = newVariantGroup(name, variantPaths)
		addToGroup(variantGroup, group)
		if targets
            targets.each { |target|
                # create PBXBuildFile
                uuidBuildFile = newObject('PBXBuildFile', {'fileRef' => variantGroup, 'comment' => name})
				uuidBuildPhase = ensureBuildPhaseForTarget('PBXResourcesBuildPhase', target)
                @p['objects'][uuidBuildPhase]['files'].push(uuidBuildFile)
			}
		end
		variantGroup
	end
	
    # An aggregate target may run scripts and have dependencies, but does not compile/link code.
	def newAggregateTarget(name, dependencies = [], buildConfigurationList = nil)
		buildConfigurationList = newProductBuildConfigurationList(name) unless buildConfigurationList
        uuid = newObject('PBXAggregateTarget', {
                         'buildConfigurationList' => buildConfigurationList,
                         'buildPhases' => [],
                         'dependencies' => dependencies,
                         'name' => name, 
                         'productName' => name,
                         'comment' => "target #{name}"
                         })
        @p['objects'][self.project]['targets'].push(uuid)
		uuid
	end
	
	def newContainerItemProxy(containerPortal, remoteTargetOrProductID, remoteTargetOrProductName, proxyType)
        # PROXYTYPE_TARGET, PROXYTYPE_PRODUCT
        newObject('PBXContainerItemProxy', {
                  'containerPortal' => containerPortal,
                  'proxyType' => proxyType,
                  'remoteGlobalIDString' => remoteTargetOrProductID,
                  'remoteInfo' => remoteTargetOrProductName
                  })
	end
	
	def newTargetDependency(target, targetProxy)
        newObject('PBXTargetDependency', {'target' => target, 'targetProxy' => targetProxy})
	end
	
	def newLocalTargetDependency(target)
        targetName = getObjectProperty(target, 'name')
		containerItemProxy = newContainerItemProxy(self.project, target, targetName, @PROXYTYPE_TARGET)
		targetDependency = newTargetDependency(target, containerItemProxy)
	end
	
    # For creating a reference to an external project (used for creating a dependency on a target of that project)
    def newExternalProject(externalProjectPath)
        # project path is for the .xcodeproj package, not the .pbxproject file. Correct automatically.
        externalProjectPath = File.dirname(externalProjectPath) if File.extname(externalProjectPath) == '.pbxproject'
        $stderr.puts "WARNING: newExternalProject expects projects to have .xcodeproj extension" if File.extname(externalProjectPath) != '.xcodeproj'
        newFileReference(externalProjectPath, 'wrapper.pb-project')
    end
    
    # An external product reference is used for creating a dependency on the output of another project.
    def newExternalProduct(externalProductFileName, fileType, containerItemProxy)
        # serious error: containerItemProxy undefined or is the wrong type of proxy.
        throw :bad_container_item_proxy unless @p['objects'].include?(containerItemProxy) && @p['objects'][containerItemProxy]['isa'] == 'PBXContainerItemProxy' && @p['objects'][containerItemProxy]['proxyType'] == @PROXYTYPE_PRODUCT
        
        newObject('PBXReferenceProxy', {
                  'path' => externalProductFileName,
                  'fileType' => fileType,
                  'remoteRef' => containerItemProxy, # The containerItemProxy for the product (@PROXYTYPE_PRODUCT)
                  'sourceTree' => 'BUILT_PRODUCTS_DIR'
                  })
    end
    
    # For external dependencies, we are dependent upon a target AND a product (generally the product of the same target).
    # TODO: We could have dependencies on multiple target/products within a single project.
    def newExternalTargetDependency(externalProjectPath, externalTargetUUID, externalTargetName, externalProductUUID, externalProductName)
        unless isID?(externalTargetUUID) && isID?(externalProductUUID)
            $stderr.puts "ERROR: invalid external target id '#{externalTargetUUID}'" unless isID?(externalTargetUUID)
            $stderr.puts "ERROR: invalid external product id '#{externalProductUUID}'" unless isID?(externalProductUUID)
            throw :invalid_parameter
        end
        # We need a reference to the project file..
        xprojRef = newExternalProject(externalProjectPath)
        # Add the project file to the main group.. (REVIEW: Do we want these elsewhere? Either automatically, or as an option?)
        addToGroup(xprojRef, self.rootGroup)
        # We need container item proxies for the external target and product..
        targetContainerItemProxy = newContainerItemProxy(xprojRef, externalTargetUUID, externalTargetName, @PROXYTYPE_TARGET)
        productContainerItemProxy = newContainerItemProxy(xprojRef, externalProductUUID, externalProductName, @PROXYTYPE_PRODUCT)
        # We need a reference proxy for the external product (this takes the place of a PBXFileReference)..
        externalProduct = newExternalProduct(externalProductName, getFileTypeForFile(externalProductName), productContainerItemProxy)
        # We need a new 'Products' group to hold the reference to the external product...
        productGroupForExternalProduct = newGroupExplicit('Products', nil)
        # Add this product group to the global list..
        setObjectProperty(self.project, 'productReferences', []) unless objectHasProperty?(self.project, 'productReferences')
        @p['objects'][self.project]['productReferences'].push(productGroupForExternalProduct)
        # Add the product reference proxy to that product group..
        addToGroup(externalProduct, productGroupForExternalProduct)
        # Create the target dependency..
        targetDependency = newObject('PBXTargetDependency', {'name' => externalTargetName, 'targetProxy' => targetContainerItemProxy})
        # RETURN targetDependency
    end
    
    # A native target compiles/links to produce some sort of code (app, library, etc).
    # Specific sub types follow.
	def newNativeTarget(name, dependencies, buildConfigurationList, productType, explicitFileType)
        uuid = newObject('PBXNativeTarget', {
                         'buildConfigurationList' => buildConfigurationList,
                         'buildPhases' => [],
                         'buildRules' => [],
                         'dependencies' => dependencies,
                         'name' => self.strip_ext(name),
                         'productName' => self.strip_ext(name),
                         'productReference' => newProductFileReference(explicitFileType, name),
                         'productType' => productType,
                         'comment' => "target #{name}"
                         })
    
        @p['objects'][self.project]['targets'].push(uuid)
            
		uuid
	end
	
	def newApplicationTarget(name, dependencies = [], buildConfigurationList=nil)
		buildConfigurationList = newProductBuildConfigurationList(name) unless buildConfigurationList
		uuid = newNativeTarget(name, dependencies, buildConfigurationList, 'com.apple.product-type.application', 'wrapper.application')
        setObjectProperty(uuid, 'productInstallPath', "$(HOME)/Applications")
		uuid
	end
	
	def newCommandLineToolTarget(name, dependencies = [], buildConfigurationList=nil)
		buildConfigurationList = newProductBuildConfigurationList(name) unless buildConfigurationList
		uuid = newNativeTarget(name, dependencies, buildConfigurationList, 'com.apple.product-type.tool', 'compiled.mach-o.executable')
		uuid
	end
	
	def newStaticLibraryTarget(name, dependencies = [], buildConfigurationList=nil)
		buildConfigurationList = newProductBuildConfigurationList(name) unless buildConfigurationList
		uuid = newNativeTarget(name, dependencies, buildConfigurationList, 'com.apple.product-type.library.static', 'archive.ar')
		uuid
	end
	
	def newFrameworkTarget(name, dependencies = [], buildConfigurationList=nil)
		buildConfigurationList = newProductBuildConfigurationList(name) unless buildConfigurationList
		uuid = newNativeTarget(name, dependencies, buildConfigurationList, 'com.apple.product-type.framework', 'wrapper.framework')
#		self.o(uuid)['DYLIB_COMPATIBILITY_VERSION'] = 1
#		self.o(uuid)['DYLIB_CURRENT_VERSION'] = 1
#		self.o(uuid)['FRAMEWORK_VERSION'] = 'A'
        setObjectProperty(uuid, 'productInstallPath', "$(HOME)/Library/Frameworks")
		uuid
	end
	
	def addTargetDependencies(target, dependsUponTargets = [])
		dependsUponTargets.each { |dependsUponTarget|
            @p['objects'][target]['dependencies'].push(dependsUponTarget)
		}
	end
	
	def addLocalTargetDependencies(target, dependsUponTargets = [])
		dependencies = dependsUponTargets.collect {|tid| newLocalTargetDependency(tid) }
		addTargetDependencies(target, dependencies)
	end
	
	def newProject(args)
        organization      = args[:organization]      || ''
        developmentRegion = args[:developmentRegion] || @DEFAULT_DEVELOPMENT_LANGUAGE
        uuid = newObject('PBXProject', {
                         'attributes'      => {'ORGANIZATIONNAME' => organization},
                         'buildConfigurationList' => newStandardProjectBuildConfigurationList(args[:projectRoot] || nil),
                         'compatibilityVersion' => @COMPATIBILITY_VERSION,
                         'developmentRegion' => developmentRegion,
                         'hasScannedForEncodings' => 0,
                         'knownRegions'    => args[:knownRegions] || [developmentRegion],
                         'mainGroup'       => newGroupExplicit(nil, nil, args[:projectRoot] || nil),
                         'productRefGroup' => @productRefGroup = newGroupExplicit('Products', nil),
                         'productDirPath'  => args[:productDirPath] || '',
                         'projectRoot'     => args[:projectRoot]    || '',
                         'targets'         => []
                         })
        @p['rootObject'] = uuid unless @p.include?('rootObject')
        if args.include?(:xcconfig) 
            fref = newSourceFile(args[:xcconfig], @p['objects'][uuid]['mainGroup'], [])
            setProjectConfigurationFile(fref)
        end
        uuid
    end
	
	def finish
		unless @isFinished_
			addToGroup(@productRefGroup, rootGroup)
			@isFinished_ = true
		end
	end

	# configurationName :== ['Debug', 'Release', '*']
	def setProjectConfigurationFile(fref_xcconfig, configurationName='*', clearExistingSettings = true)
        buildConfigurationList = getObjectProperty(self.project, 'buildConfigurationList')
        getObjectProperty(buildConfigurationList, 'buildConfigurations').each { |bc|
			if '*' == configurationName || getObjectProperty(bc, 'name') == configurationName
                setObjectProperty(bc, 'baseConfigurationReference', fref_xcconfig)
				if clearExistingSettings
					# Preserve the setting of PROJECT_ROOT regardless (originally set in newProject if a root was specified)
                    project_root = getObjectProperty(bc, 'buildSettings').include?('PROJECT_ROOT') ? getObjectProperty(bc, 'buildSettings')['PROJECT_ROOT'] : nil
                    setObjectProperty(bc, 'buildSettings', project_root ? {'PROJECT_ROOT' => project_root} : {})
				end
			end
		}
	end
	
	
	# configurationName :== ['Debug', 'Release', '*']
	def setTargetConfigurationFile(target, fref_xcconfig, configurationName='*', clearExistingSettings = true)
        buildConfigurationList = getObjectProperty(target, 'buildConfigurationList')
        getObjectProperty(buildConfigurationList, 'buildConfigurations').each { |bc|
			if '*' == configurationName || getObjectProperty(bc, 'name') == configurationName
                setObjectProperty(bc, 'baseConfigurationReference', fref_xcconfig)
                setObjectProperty(bc, 'buildSettings', {}) if clearExistingSettings
			end
		}
	end
	
	def project
		@p['rootObject']
	end
	
	def rootGroup
		@p['objects'][self.project]['mainGroup']
	end
	
	def projectBuildConfigurationList
        @p['objects'][self.project]['buildConfigurationList']
	end
	
end

