<#

.SYNOPSIS
Installs an app for a Splunk Universal Forwarder.
.DESCRIPTION
Installs an app for a Splunk Universal Forwarder.
The specified app folder is copied to the apps directory, and the Universal Forwarder is restarted so the new configurations are in effect.
This requires the presence of a version file to identify the version of the Splunk app.
The version file should be named x.y.version, where x.y is the version number.
The version file should be placed in the app's default directory.
.NOTES
Author: Geoff Nelson
Contact: gnelson@austin.utexas.edu
.PARAMETER appFolderName
The folder name for the Splunk app to install.
.PARAMETER appSourcePath
The path that contains the Splunk app folder that will be installed.  This can be somewhere on the local file system or a file share.
If not provided, the default is the current path.
When using this script with an Application in SCCM, you do not need to set this.  The working path by default (when not specifying a value for 'Installation start in' on the Deployment Type) is the relevant ccm cache folder.
.PARAMETER eventLogSource
The value that Source is set to on events logged to the Windows Application Log.
If not provided, the default is ut_splunkforwarder
.PARAMETER unblockFiles
Whether to check for blocked files in the installed app folder, and unblock any files that are blocked.
If not provided, the default value is true.
.EXAMPLE
Install-SplunkUFApp.ps1 -appFolderName "inputs_winlog"
Will install the app with folder name inputs_winlog located in the current working directory.
.EXAMPLE
Install-SplunkUFApp.ps1 -appFolderName "inputs_winlog" -appSourcePath "\\server1\share\splunk_apps\"
Will install the app with folder name inputs_winlog from content located in \\server1\share\splunk_apps\.
.EXAMPLE
Install-SplunkUFApp.ps1 -appFolderName "inputs_winlog" -appSourcePath "C:\DFSR\content\splunk_apps\" -eventLogSource "SplunkUFApp"
Will install the app with folder name inputs_winlog from content located in C:\DFSR\content\splunk_apps\.  Events written to the Application event log will have Source set to SplunkUFApp

#>

# Parameters
param([parameter(Mandatory=$true)] [string]$appFolderName, [parameter(Mandatory=$false)] [string]$appSourcePath = ".", [parameter(Mandatory=$false)] [string]$eventLogSource = "ut_splunkforwarder", [parameter(Mandatory=$false)] [bool]$unblockFiles = $true)

# Construct the path for the app folder in the source path
$appFolderNameInSourcePath = Join-Path -Path $appSourcePath -ChildPath $appFolderName

# Add the specified eventLogSource as a Source for the Application Log if it is not already present
IF (![System.Diagnostics.EventLog]::SourceExists("$eventLogSource")) {New-EventLog -LogName Application -Source $eventLogSource}

Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -EventID 990 -Message "Beginning the install of a Splunk Universal Forwarder app.`nAppFolderName: $appFolderName`nAppSourcePath: $appSourcePath`nUnblockFiles: $unblockFiles`nStatusMsg: App install starting"

function Write-SplunkUFAppInstallFailedEvent
    {
    Write-EventLog -LogName Application -Source $eventLogSource -EntryType Error -EventID 999 -Message "Failed to install a Splunk Universal Forwarder app.`nAppFolderName: $appFolderName`nStatusMsg: App install failed"
    }

# Initialise restartFlag variable.  Only restart the Splunk Universal Forwarder if the app was successfully installed.
$restartFlag = 0

# Initialise the warningsCount variable
$warningsCount = 0

# Verify the app folder exists
IF (Test-Path -Path $appFolderNameInSourcePath)
    {
    Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -EventID 914 -Message "The app source content was found.  Installation can proceed.`nAppFolderName: $appFolderName`nAppSourcePath: $appSourcePath`nAppPath: $appFolderNameInSourcePath`nStatusMsg: App source content was found"
    }
    else
    {
    # If the app source can not be found, write event to log and exit script
    Write-EventLog -LogName Application -Source $eventLogSource -EntryType Error -EventID 913 -Message "The app source content was not found, so installation can not continue.`nAppFolderName: $appFolderName`nAppSourcePath: $appSourcePath`nStatusMsg: App source content was not found"
    Write-SplunkUFAppInstallFailedEvent
    Exit
    }

# Get the version of the app to be installed
IF ($versionFileToBeInstalled = (Get-ChildItem -Path (Join-Path -Path $appFolderNameInSourcePath -ChildPath "default") -Filter *.version).Name)
    {
    $versionToBeInstalled =  $versionFileToBeInstalled -replace ".version", ""
    }
    else
    {
    # If the version file was not found, write event to log and exit script 
    Write-EventLog -LogName Application -Source $eventLogSource -EntryType Error -EventID 915 -Message "An app version file was not found in the source content.  This is required for the app install/upgrade process.`nAppFolderName: $appFolderName`nStatusMsg: Can not detect the version of the app to be installed"
    Write-SplunkUFAppInstallFailedEvent
    Exit
    }

# If the app is already installed (the app folder and version file are present)
IF (Test-Path "$env:ProgramFiles\SplunkUniversalForwarder\etc\apps\$appFolderName\default\*.version")
    {
    # Get the version file and determine the version installed from the version file
    $installedAlreadyFile=(Get-Item "$env:ProgramFiles\SplunkUniversalForwarder\etc\apps\$appFolderName\default\*.version").Name
    $installedAlready=$installedAlreadyFile -replace ".version", ""
    
    # If the installed version is the same as the version to be installed - write event to log and exit the script.
    IF ($versionToBeInstalled -eq $installedAlready)
        {
        Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -EventID 912 -Message "An existing app version file was detected ($installedAlreadyFile) for the same version to be installed ($versionFileToBeInstalled).`nAppFolderName: $appFolderName`nStatusMsg: App and version already installed"
        Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -EventID 996 -Message "No action is required, the app and version is already installed.`nAppFolderName: $appFolderName`nStatusMsg: App already installed"
        Exit
    }
    # Otherwise this is an ugrpade to a newer version of the app
    Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -EventID 909 -Message "An existing app version file was detected ($installedAlreadyFile) that is different from the version to be installed ($versionFileToBeInstalled).  This is an attempt to update the app.`nAppFolderName: $appFolderName`nStatusMsg: App detected to be updated"
    TRY
        {
        Remove-Item -Path "$env:ProgramFiles\SplunkUniversalForwarder\etc\apps\$appFolderName\default\*.version" -Force -ErrorAction Stop
        Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -EventID 910 -Message "Successfully removed the existing app version file ($installedAlreadyFile).`nAppFolderName: $appFolderName`nStatusMsg: App version file successfully removed existing app version file"
        }
    CATCH
        {
        Write-EventLog -LogName Application -Source $eventLogSource -EntryType Warning -EventID 911 -Message "Failed to remove the existing app version file.  App installation will continue, but there may be duplicate version files present.`nAppFolderName: $appFolderName`nStatusMsg: Failed to remove existing app version file"
        $warningsCount++
        }
    }

# Copy the app folder to the Splunk Universal Forwarder apps directory
TRY
	{
	Copy-Item -Path $appFolderNameInSourcePath -Destination "$env:ProgramFiles\SplunkUniversalForwarder\etc\apps" -Recurse -Force -ErrorAction Stop
	$installedNow=$null=(($(Get-Item $env:ProgramFiles\SplunkUniversalForwarder\etc\apps\$appFolderName\default\*.version).Name) -replace ".version", "")
    IF ($installedNow -eq $null -OR $installedNow -eq "") {$installedNow = "<version file was not detected>"}
    Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -EventID 901 -Message "The app folder was successfully copied to the apps directory.`nAppFolderName: $appFolderName`nStatusMsg: Successfully installed app content"
	$restartFlag = 1
	}
CATCH
	{
	Write-EventLog -LogName Application -Source $eventLogSource -EntryType Error -EventID 902 -Message "The app folder failed to copy to the apps directory.`nAppFolderName: $appFolderName`nStatusMsg: Failed to install app content"
	$restartFlag = 0
	}

# Check for blocked files in the installed app directory, and unblock if any are found
IF ($unblockFiles)
    {
    $blockedFiles = @(Get-ChildItem -Path "$env:ProgramFiles\SplunkUniversalForwarder\etc\apps\$appFolderName" -Recurse | Get-Item -Stream "Zone.Identifier" -ErrorAction SilentlyContinue | Where-Object {$_.Stream -eq "Zone.Identifier"})
    IF ($blockedFiles.count -gt 0)
        {
        Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -EventID 916 -Message "There were $($blockedFiles.count) blocked files found in the installed app directory.  These files will be unblocked.`nAppFolderName: $appFolderName`nBlockedFiles: $($blockedFiles.FileName -join "; ")`nStatusMsg: Blocked files found"
        TRY
            {
            Unblock-File -Path $blockedFiles.Filename -ErrorAction Stop
            Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -EventID 918 -Message "There blocked files found in the installed app directory have been unblocked.`nAppFolderName: $appFolderName`nStatusMsg: Files unblocked"
            }
        Catch
            {
            Write-EventLog -LogName Application -Source $eventLogSource -EntryType Warning -EventID 919 -Message "Failed to unblock one or more files in the installed app directory`nAppFolderName: $appFolderName`nStatusMsg: Failed to unblock file(s)"
            $warningsCount++
            }
        }
        ELSE
        {
        Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -EventID 917 -Message "There were no blocked files found in the installed app directory.`nAppFolderName: $appFolderName`nStatusMsg: Blocked files not found"
        }
    }

# If flagged, restart the Splunk Forwarder for the new inputs to become effective
IF ($restartFlag -eq 1)
	{
	TRY
		{
		Start-Sleep -Seconds 2
        Restart-Service SplunkForwarder -ErrorAction Stop
		Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -EventID 903 -Message "The Splunk Universal Forwarder was successfully restarted in order for the configuration from the newly installed app to take effect.`nAppFolderName: $appFolderName`nStatusMsg: Restarted the Splunk Universal Forwarder"
		}
	CATCH
		{
		Write-EventLog -LogName Application -Source $eventLogSource -EntryType Warning -EventID 904 -Message "The Splunk Universal Forwarder failed to restart.  Configuration from the newly installed app is not in effect.`nAppFolderName: $appFolderName`nStatusMsg: Failed to restart the Splunk Universal Forwarder"
        $warningsCount++
		}
	}

# Log the completion of the install, including whether there were any warnings
IF ($warningsCount -eq 0)
    {
    Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -EventID 997 -Message "Successfully completed the install a Splunk Universal Forwarder app.`nAppFolderName: $appFolderName`nStatusMsg: App install completed"
    }
    else
    {
    Write-EventLog -LogName Application -Source $eventLogSource -EntryType Warning -EventID 998 -Message "Completed the install a Splunk Universal Forwarder app with one or more warnings.`nAppFolderName: $appFolderName`nStatusMsg: App install completed with warning(s)"
    }
