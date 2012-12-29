#
# XcodeProject
#
# High-level ("sane") interface for creating Xcode projects from Ruby.
# v1.0 June 2011 by Dan Wright.
# v1.1.1 April 2012 by Dan Wright.
# v1.2 December 2012 by Dan Wright.
# Licensed under the MIT license. Part of the bsxtools project.
# git://github.com/danwr/bsxtools.git
#
# Usage:
#
# (1) Create an XcodeProject object
# (2) Create groups
# (3) Create targets
# (4) Add files to groups and (optionally) to target(s)
# (5) Write out the project
#
# Brief example:
# 	xp = XcodeProject.new
# 	xp.newProject({})
# 	xp.newGroup("Classes", "sources")
# 	xp.newGroup("Other Sources", "sources")
# 	xp.newGroup("Resources", "resources")
# 	xp.newGroup("Frameworks")
# 	mainTarget = xp.newApplicationTarget("MyApp.app")
# 	xp.newSourceFile("main.m", "Other Sources", [mainTarget])
# 	xp.newSourceFile("MyAppDelegate.m", "Classes", [mainTarget])
# 	xp.newHeaderFile("MyAppDelegate.h", "Classes")
# 	xp.newFramework("Cocoa.framework", [mainTarget])
# 	xp.newLocalizedResource("MainMenu.xib", ["English.lproj"], "Resources", [mainTarget])
#	xp.setProjectConfigurationFile(frefProjectXcconfig)
#	xp.setTargetsConfigurationFile([mainTarget], 'MyAppTarget.xcconfig')
# 	xp.write("#{ENV['HOME']}/Documents/MyApp.xcodeproj")
#

require 'xcodeproject/pbxprojWriter.rb'
require 'xcodeproject/pbxprojReader.rb'

$_registeredProjects = {}

def registeredProjects
    $_registeredProjects.keys
end

def registeredProject(name)
    $_registeredProjects[name.downcase]
end

class XcodeProject

    def initialize
        super
        @proj = PbxprojWriter.new
        register(@PROJECT) if defined?(@PROJECT)
    end
    
    def register(name)
        $_registeredProjects[name.downcase] = self
    end
        
    def addFileTypes(mappings = {})
        @proj.addFileTypes(mappings)
    end
    
    def newBuildConfiguration(name, settings)
        @proj.newBuildConfiguration(name, settings)
    end
    
    def newProjectBuildConfiguration(name, productName)
        @proj.newProjectBuildConfiguration(name, productName)
    end
    
    def newStandardBuildConfigurationList
        @proj.newStandardBuildConfigurationList
    end
    
    def newProductBuildConfigurationList(productName)
        @proj.newProductBuildConfigurationList(productName)
    end
    
    def setKeyValueInBuildConfigurationList(buildConfigurationList, key, value)
        @proj.setKeyValueInBuildConfigurationList(buildConfigurationList, key, value)
    end

    def newGroup(nameSpec, path=nil, sourceTree=nil)
        @proj.newGroup(nameSpec, path, sourceTree)
    end
    
    def addToGroup(fileOrGroupOrVariantRef, targetGroup)
        @proj.addToGroup(fileOrGroupOrVariantRef, targetGroup)
    end
    
    def newProductFileReference(explicitFileType, path, sourceTree=nil)
        @proj.newProductFileReference(explicitFileType, path, sourceTree)
    end
    
    def newFileReference(path, fileType)
        @proj.newFileReference(path, fileType)
    end
    
    def findFileReference(path)
        @proj.findFileReference(path)
    end
    
    def newBuildFile(fileRef, target, options = {}, buildPhase = 'PBXSourcesBuildPhase')
        throw :bad_arg if options && options.class != Hash
        throw :bad_arg if !buildPhase || buildPhase.class != String
        options['buildPhase'] = buildPhase
        @proj.newBuildFile(fileRef, target, options)
    end
    
    # setFileReferenceUsesTabs overrides the Xcode default setting for 
    # tabs-vs-spaces for a specific file reference.
    def setFileReferenceUsesTabs(fileRefUuid, usesTabs)
        @proj.setFileReferenceUsesTabs(fileRefUuid, usesTabs)
    end
    
    # Explicitly set the text encoding used by a file; we understand 'utf16'
    # for now (this is the only common override).
    def setFileReferenceTextEncodingName(fileRefUuid, textEncodingName)
        throw :bad_arg unless fileRefUuid && fileRefUuid.class == String
        textEncoding = @proj.textEncodingForName(textEncodingName)
        @proj.setFileReferenceTextEncoding(fileRefUuid, textEncoding)
    end
    
    def newShellScriptBuildPhase(name, target, shellScript, options={})
        @proj.newShellScriptBuildPhase(name, target, shellScript, options)
    end

    def newCopyFrameworksBuildPhase(target, options={})
        @proj.newCopyFrameworksBuildPhase(target, options)
    end
    
    def addFrameworkToCopyPhase(path, target)
        fileRef = findFileReference(path)
        fileRef = newFileReference(path, target) unless fileRef
        @proj.addFrameworkToCopyPhase(path, fileRef, target)
    end
    
    def newSourceFile(path, group, targets, sourceTree=nil, compilerFlags=nil)
        options = {}
        options['COMPILER_FLAGS'] = "#{compilerFlags}" if compilerFlags
        @proj.newSourceFile(path, group, targets, sourceTree, 'PBXSourcesBuildPhase', options)
    end
    
    def newBuiltSourceFile(path, group, sourceTree=nil, targets=[], compilerFlags=nil)
        throw :bad_arg if sourceTree && sourceTree.class != String
        throw :bad_arg unless targets && targets.class == Array
        throw :bad_arg if compilerFlags && compilerFlags.class != String
        options = {}
        options['COMPILER_FLAGS'] = "#{compilerFlags}" if compilerFlags && compilerFlags != ""
        @proj.newBuiltSourceFile(path, group, targets, sourceTree, 'PBXSourcesBuildPhase', options)
    end
    
    def newHeaderFile(path, group, sourceTree=nil)
        @proj.newSourceFile(path, group, [], sourceTree)
    end
    
    def newBuiltHeaderFile(path, group, sourceTree)
        @proj.newBuiltSourceFile(path, group, [], sourceTree)
    end
    
    def newIgnoredFile(path, group, sourceTree=nil)
        @proj.newSourceFile(path, group, [], sourceTree)
    end
    
    def newResourceFile(path, group, targets, sourceTree=nil)
        @proj.newSourceFile(path, group, targets, sourceTree, 'PBXResourcesBuildPhase')
    end
    
    def newBuiltResourceFile(name, group, targets=[])
        @proj.newBuiltResourceFile(name, group, targets)
    end
    
    def newFramework(name, targets=[])
        @proj.newFramework(name, targets)
    end
    
    def newUsrLib(name, targets=[])
        @proj.newUsrLib(name, targets)
    end

    def newLibrary(path, group, targets, sourceTree=nil)
        @proj.newSourceFile(path, group, targets, sourceTree, 'PBXFrameworksBuildPhase')
    end
    
    def newFolder(path, group, targets, sourceTree=nil)
        @proj.newFolderReference(path, group, targets, sourceTree)
    end
    
    def newLocalizedResource(name, variantPaths, group, targets)
        @proj.newLocalizedResource(name, variantPaths, group, targets)
    end
    
    def newLocalTargetDependency(target)
        @proj.newLocalTargetDependency(target)
    end
    
    def newAggregateTarget(name, dependencies=[], buildConfigurationList=nil)
        @proj.newAggregateTarget(name, dependencies, buildConfigurationList)
    end
    
    def newApplicationTarget(name, dependencies=[], buildConfigurationList=nil)
        @proj.newApplicationTarget(name, dependencies, buildConfigurationList)
    end
    
    def newCommandLineToolTarget(name, dependencies=[], buildConfigurationList=nil)
        @proj.newCommandLineToolTarget(name, dependencies, buildConfigurationList)
    end
    
    def newStaticLibraryTarget(name, dependencies=[], buildConfigurationList=nil)
        @proj.newStaticLibraryTarget(name, dependencies, buildConfigurationList)
    end
    
    def newFrameworkTarget(name, dependencies=[], buildConfigurationList=nil)
        @proj.newFrameworkTarget(name, dependencies, buildConfigurationList)
    end
    
    def newShellScriptTarget(name, shellScript, options={})
        target = @proj.newAggregateTarget(name)
        buildPhase = @proj.newShellScriptBuildPhase(name, target, shellScript, options)
        target
    end
    
    def addTargetDependencies(target, dependsUponTargets=[])
        @proj.addTargetDependencies(target, dependsUponTargets)
    end
    
    def addLocalTargetDependencies(target, dependsUponTargets=[])
        dependencies = dependsUponTargets.collect {|tid| @proj.newLocalTargetDependency(tid)}
        @proj.addTargetDependencies(target, dependencies)
    end
    
    def newExternalTargetDependency(externalProjectPath, externalTargetID, externalTargetName, externalProductID, externalProductName)
        @proj.newExternalTargetDependency(externalProjectPath, externalTargetID, externalTargetName, externalProductID, externalProductName)
    end

    def getExternalProjectInfo(externalProjectPath)
        begin
            externalProjectPath = File.join(externalProjectPath, 'project.pbxproj') if File.extname(externalProjectPath) == '.xcodeproj'
            reader = PbxprojReader.new(externalProjectPath)
            reader.parse!
            projectID = reader.project
            projectObject = reader.objectOfClass(projectID, 'PBXProject')
            allTargets = projectObject['targets'].to_a
            allTargetInfo = allTargets.collect { |target| 
                targetObject = reader.objectForUUID(target) 
                targetName = targetObject.include?('name') ? targetObject['name'].to_s : nil
                productName = targetObject.include?('productName') ? targetObject['productName'].to_s : nil
                productRef = targetObject.include?('productReference') ? targetObject['productReference'].to_s : nil
                productType = targetObject.include?('productType') ? targetObject['productType'].to_s : nil
                {'uuid' => target.to_s, 'name' => targetName, 'productName' => productName, 'productRef' => productRef, 'productType' => productType}
            }
            targetNameHash = {}
            allTargetInfo.each { |targetInfo|
                $stderr.puts "WARNING: multiple targets in project have the same name for project #{externalProjectPath}" if targetInfo['name'] != nil && targetNameHash.include?(targetInfo['name'])
                targetNameHash[targetInfo['name']] = targetInfo if targetInfo['name'] != nil
            }
            
            {'project' => projectID,
                'targetArray' => allTargetInfo,
                'targetHash' => targetNameHash}
        rescue
            $stderr.puts "ERROR: XcodeProject::getExternalProjectInfo unable to parse project and extract list of targets for '#{externalProjectPath}'"
            throw :unable_to_parse_project
        end
    end
    
    def addExternalTargetDependency(target, externalProjectPath, externalTargetName)
        projectInfo = getExternalProjectInfo(externalProjectPath)
        unless projectInfo['targetHash'].include?(externalTargetName)
            $stderr.puts "ERROR: Unable to create external dependency to project '#{File.basename(externalProjectPath)}' target '#{externalTargetName}' because there is no target with that name."
            # stop now, because the project would be malformed and this error message likely overlooked.
            throw :unable_to_create_external_dependency
        end
        targetInfo = projectInfo['targetHash'][externalTargetName]
        externalDependency = newExternalTargetDependency(externalProjectPath, targetInfo['uuid'], externalTargetName, targetInfo['productRef'], targetInfo['productName'])
        addTargetDependencies(target, [externalDependency])
    end
    
    def newProject(args)
        @proj.newProject(args || {})
    end
    
    def newProjectConfigurationFile(path, group=nil, configurationName='*', clearExistingSettings = true)
        fref = @proj.newSourceFile(path, group || @proj.rootGroup, [])
        @proj.setProjectConfigurationFile(fref, configurationName, clearExistingSettings)
    end
    
    def newTargetsConfigurationFile(targets, path, group=nil, configurationName='*', clearExistingSettings=true)
        fref = @proj.newSourceFile(path, group || @proj.rootGroup, [])
        targets = [targets] unless targets.instance_of?(Array)
        targets.each { |tid| @proj.setTargetConfigurationFile(tid, fref, configurationName, clearExistingSettings) }
    end
        
    def project
        @proj.project
    end
    
    def rootGroup
        @proj.rootGroup
    end

    def projectBuildConfigurationList
        @proj.projectBuildConfigurationList
    end
    
    def write(path)
        @proj.write(path)
    end

end
