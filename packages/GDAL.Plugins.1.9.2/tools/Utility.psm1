################################################################################################## 
#
# Utility functions to deploy GDAL native binaries for common project types
#
# These functions are greatly inspired by VS.psm1 of System.Data.SqlServerCompact
# nuget package.
#
################################################################################################## 

################################################################################################## 
function Add-BuildStep ($project, $kind, $buildCommand)
{
<#

.SYNOPSIS
Method to add a build step to the project's build events

.PARAMETER project
The project to add the step to

.PARAMETER kind
may be either "Pre" or "Post" 

.PARAMETER buildCommand
The MS-DOS command(s) to execute

#>
    if (!($kind -eq "Pre" -bor $kind -eq "Post"))
    {
        Write-Host "Only 'Pre' and 'Post' are valid kinds"
        return
    }
    
    $item = $kind + "BuildEvent"
    $currentBuildCmd = $project.Properties.Item($item).Value
    # Append our build command if it's not already there
    if (!$currentBuildCmd.Contains($buildCommand)) {
        $project.Properties.Item($item).Value += $buildCommand
    }
}

################################################################################################## 
function Remove-BuildStep ($project, $kind, $buildCommand)
{
<#

.SYNOPSIS
Method to remove a build step from the project's build events

.PARAMETER project
The project to remove the build step from

.PARAMETER kind
may be either "Pre" or "Post" 

.PARAMETER buildCommand
The MS-DOS command(s) to execute

#>
    if (!($kind -eq "Pre" -bor $kind -eq "Post"))
    {
        Write-Host "Only 'Pre' and 'Post' are valid kinds"
        return
    }
    
    $item = $kind + "BuildEvent"
    try {
        # Get the current Post Build Event cmd
        $currentBuildCmd = $project.Properties.Item($item).Value

        # Remove our post build command from it (if it's there)
        $project.Properties.Item($item).Value = $currentBuildCmd.Replace($buildCmd, '')
    } catch {
        # Accessing $project.Properties might throw
    }
}

################################################################################################## 
function Get-XCopyBuildStep($installpath, $subPath)
{
<#

.SYNOPSIS
Method to build an xcopy msdos command

.PARAMETER installpath
The root path where the files have been installed to

.PARAMETER subpath
The sub-path, relative to $installPath, where the files to xcopy are located

#>
    return Get-XCopyBuildStep2 $installpath $subPath $subPath
}

################################################################################################## 
function Get-XCopyBuildStep2($installpath, $subPath, $targetSubPath)
{
<#

.SYNOPSIS
Method to build an xcopy msdos command

.PARAMETER installpath
The root path where the files have been installed to

.PARAMETER subpath
The sub-path, relative to $installPath, where the files to xcopy are located

.PARAMETER targetSubPath
The sub-path, relative to $(TargetDir), where the files are to be copied to.

#>
    #Write-Host $dte.Solution.FullName
    #Write-Host $installPath
    #Write-Host $subPath
    #Write-Host $targetSubPath

    $solutionDir = [IO.Path]::GetDirectoryName($dte.Solution.FullName) + "\"
    $path = $installPath.Replace($solutionDir, "`$(SolutionDir)")

    $filter = $subPath + "\*.*"
    $sourcePath = Join-Path $path $filter

    return "
    if not exist `"`$(TargetDir)$targetSubPath`" md `"`$(TargetDir)$targetSubPath`"
    xcopy /s /y `"$sourcePath`" `"`$(TargetDir)$targetSubPath`""
}

################################################################################################## 
function Get-VSFileSystem 
{
<#

.SYNOPSIS
Method to get the file system inside VisualStudio

#>
    $componentModel = Get-VSComponentModel
    $fileSystemProvider = $componentModel.GetService([NuGet.VisualStudio.IFileSystemProvider])
    $solutionManager = $componentModel.GetService([NuGet.VisualStudio.ISolutionManager])
    
    $fileSystem = $fileSystemProvider.GetFileSystem($solutionManager.SolutionDirectory)
    
    return $fileSystem
}

################################################################################################## 
function Add-FilesToVSFolder ($srcDirectory, $destDirectory, $filter = "*") 
{
<#

.SYNOPSIS
Method to get the file system inside VisualStudio

.PARAMETER srcDirectory
The source directory, where the files come from 

.PARAMETER destDirectory
The destination directory, where the files are to be copied to 
(VisualStudio FileSystem)

.PARAMETER filter
the filter to apply (e.g. *.dll)
#>
    $fileSystem = Get-VSFileSystem
    ls $srcDirectory -Recurse -Filter $filter | Where-Object {!$_.PSIsContainer} | %{
        $srcPath = $_.FullName

        $relativePath = $srcPath.Substring($srcDirectory.Length + 1)
        $destPath = Join-Path $destDirectory $relativePath
        
        if (!(Test-Path $destPath)) {
            $fileStream = $null
            try {
                $fileStream = [System.IO.File]::OpenRead($_.FullName)
                $fileSystem.AddFile($destPath, $fileStream)
            } catch {
                # We don't want an exception to surface if we can't add the file for some reason
            } finally {
                if ($fileStream -ne $null) {
                    $fileStream.Dispose()
                }
            }
        }
    }
}

################################################################################################## 
function Remove-FilesFromVSFolder ($srcDirectory, $destDirectory, $filter = "*") 
{
<#

.SYNOPSIS
Method to remove files from a VisualStudio file system folder

.PARAMETER srcDirectory
The source directory, where the files originally came from 

.PARAMETER destDirectory
The destination directory, where the files are to be deleted
(VisualStudio FileSystem)

.PARAMETER filter
the filter to apply (e.g. *.dll)
#>
    $fileSystem = Get-VSFileSystem
    
    ls $srcDirectory -Recurse -Filter $filter | Where-Object {!$_.PSIsContainer} |  %{
        $relativePath = $_.FullName.Substring($srcDirectory.Length + 1)
        $fileInBin = Join-Path $destDirectory $relativePath
        if ($fileSystem.FileExists($fileInBin) -and ((Get-Item $fileInBin).Length -eq $_.Length))
        {
            # If a corresponding file exists in bin and has the exact file size as the one
            # inside the package, it's most likely the same file.
            try {
                $fileSystem.DeleteFile($fileInBin)
            } catch {
                # We don't want an exception to surface if we can't delete the file
            }
            
            $directory = Split-Path $fileInBin
            $dir = Get-Item $directory
            if ($dir.GetFiles().Count -eq 0) {
                write-host "deleting" $directory
                Remove-Item $directory
            }
        }
    }
    
    
}

################################################################################################## 
# Method to get the root entry of a project
# $project - The VisualStudio project
# 
function Get-ProjectRoot($project) 
{
<#

.SYNOPSIS
Method to get the root entry of a project

.PARAMETER project 
The VisualStudio project

#>
    try 
    {
        $project.Properties.Item("FullPath").Value
    }
    catch 
    { }
}

################################################################################################## 
function Get-ChildProjectItem($parent, $name) 
{
<#

.SYNOPSIS
Method to get a child item

.PARAMETER parent 
The parent item

.PARAMETER name 
The name of the item

#>
    try 
    {
        return $parent.ProjectItems.Item($name);
    }
    catch { }
}

################################################################################################## 
function Get-EnsuredFolder($parentFolder, $name)
{
<#

.SYNOPSIS
Method to get a project folder relative to parent. If it does not exist it will be created

.PARAMETER parentFolder 
The VisualStudio project folder

.PARAMETER name 
The name of the foleder

#>

    $item = Get-ChildProjectItem $parentFolder $name
    if(!$item) 
    {
        $item = (Get-Interface $parentFolder.ProjectItems "EnvDTE.ProjectItems").AddFolder($name)
    }
    return $item;
}

################################################################################################## 
function Remove-EmptyFolder($item) 
{
<#

.SYNOPSIS
Method to remove a project folder, if it is empty

.PARAMETER item 
The VisualStudio project folder

#>
    if($item.ProjectItems.Count -eq 0) 
    {
        (Get-Interface $item "EnvDTE.ProjectItem").Delete()
    }
}

################################################################################################## 
function Add-ItemToProject($folder, $src, $itemtype = "None") 
{
<#

.SYNOPSIS
Method to add an item to a project. The file is copied to a location relative to
the project folder.

.PARAMETER folder 
The VisualStudio project folder

.PARAMETER src 
The path of the file(s) to add to the folder

.PARAMETER itemType 
The build type

#>
    try 
    {
        $newitem = (Get-Interface $folder.ProjectItems "EnvDTE.ProjectItems").AddFromFileCopy($src)
        $newitem.Properties.Item("ItemType").Value = $itemtype 
    }
    catch [System.Exception]
    { 
        Write-Host $folder.Name ", " $src, ", " $itemType
        Write-Host $Error
    }
}

################################################################################################## 
# Method to remove an item from a project folder.
# $folder   - The VisualStudio project folder
# $name     - The name of the item to remove
# 
function Remove-ItemFromProject($folder, $name) 
{
<#

.SYNOPSIS
Method to remove an item from a project folder.

.PARAMETER folder 
The VisualStudio project folder

.PARAMETER name 
The name of the item to remove

#>
    $item = Get-ChildProjectItem $folder $name
    if($item) 
    {
        (Get-Interface $item "EnvDTE.ProjectItem").Delete()
    }
    else
    {
       Write-Host $name.Name "not found in" $folder.Name
    }
}

################################################################################################## 
function Add-ItemsToProject($target, $srcDirectory, $filter = "*", $itemtype = "None") 
{
<#

.SYNOPSIS
Method to (recursivly) add all items in a path to a project. Each file is copied to a location 
relative to the project folder.

.PARAMETER folder 
The VisualStudio project folder

.PARAMETER srcDirectory 
The path of the file(s) to add to the folder

.PARAMETER filter 
The filter of files to include

.PARAMETER itemType 
The build type

#>
    ls $srcDirectory -Recurse -Filter $filter | Where-Object {!$_.PSIsContainer} | %{
        $srcPath = $_.FullName

        $destPath = $srcPath.Substring($srcDirectory.Length + 1)
        $destFolder = Split-Path $destPath
        $item = $target
        foreach ($folderName in $destFolder.Split("`\/"))
        {
            $item = Get-EnsuredFolder $item $folderName
        }
        Add-ItemToProject $item $srcPath $itemtype
    }
}

################################################################################################## 
function Remove-ItemsFromProject($target, $srcDirectory, $filter = "*") 
{
<#

.SYNOPSIS
Method to remove all files from a project folder that are also present in $srcDirectory.

.PARAMETER folder 
The VisualStudio project folder

.PARAMETER srcDirectory 
The directory where the original files are in

.PARAMETER filter 
The filter of files to include

.PARAMETER itemType 
The build type

#>
    ls $srcDirectory -Recurse -Filter $filter | Where-Object {!$_.PSIsContainer} | %{
        $srcPath = $_.FullName

        $destPath = $srcPath.Substring($srcDirectory.Length + 1)
        $destFolder = Split-Path $destPath
        $item = $target
        foreach ($folderName in $destFolder.Split("`\/"))
        {
            $item = Get-ChildProjectItem $item $folderName
        }
        Remove-ItemFromProject $item $_.Name
        Remove-EmptyFolderCascade $item $target
    }
}

function Remove-EmptyFolderCascade($item, $target) {
    
    while($item.ProjectItems.Count -eq 0 -band $item -ne $target)
    {
        $parent = $item.Parent
        (Get-Interface $item "EnvDTE.ProjectItem").Delete()
        $item = $parent
    }
}

Export-ModuleMember -function Add-BuildStep, Remove-BuildStep, Get-XCopyBuildStep, Add-FilesToVSFolder, Remove-FilesFromVSFolder, Get-ProjectRoot, Get-ChildProjectItem, Add-ItemToProject, Add-ItemsToProject, Remove-ItemFromProject, Remove-ItemsFromProject, Remove-EmptyFolder, Get-EnsuredFolder