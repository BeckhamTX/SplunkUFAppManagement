# Install-SplunkUFApp
# Version 1.2
# This script will install a Splunk app for a Universal Forwarder by its folder name
# Written By: Geoff Nelson, The University of Texas at Austin, gnelson@austin.utexas.edu
# Written: 22 March 2016
# Last Updated: March 2021

# Parameters
param([parameter(Mandatory=$true)] $appFolderName)

# Start of configuration section ------------------------------
$eventLogSource = "ut_splunkforwarder"
# End of configuration section --------------------------------

<#.PARAMETER appFolderName
The folder name of the app to install.  This parameter is required.

.EXAMPLE
Install-SplunkApp.ps1 -appFolderName ut_splunkforwarder_inputs_winlog
This will install (copy) the ut_splunkforwarder_inputs_winlog directory to the Splunk apps directory, and then restart the Splunk Forwarder for the new inputs to take effect.
#>


# Add specified eventLogSource as a Source for the Application Log if it is not already present
IF (![System.Diagnostics.EventLog]::SourceExists("$eventLogSource")) {New-EventLog -LogName Application -Source $eventLogSource}

# Initialise restartFlag variable.  Only restart the Forwarder if the app was successfully installed.
$restartFlag = 0

# Determine if an earlier version of the app is installed.  If so, delete the version file (which is used by SCCM to detect installation of a specific version of the app.)
IF (Test-Path $env:ProgramFiles\SplunkUniversalForwarder\etc\apps\$appFolderName\default\*.version)
    {
    $installedAlreadyFile=(Get-Item $env:ProgramFiles\SplunkUniversalForwarder\etc\apps\$appFolderName\default\*.version).Name
    $installedAlready=$installedAlreadyFile -replace ".version", ""
    Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -EventID 909 -Message "An existing app version file was detected ($installedAlreadyFile).  This is an attempt to update or reinstall this app.`nAppFolderName: $appFolderName`nStatusMsg: An existing version of the app was detected ($installedAlready)"
    TRY
        {
        Remove-Item -Path $env:ProgramFiles\SplunkUniversalForwarder\etc\apps\$appFolderName\default\*.version -Force -ErrorAction Stop
        Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -EventID 910 -Message "Successfully removed the existing app version file.`nAppFolderName: $appFolderName`nStatusMsg: Successfully removed existing app version file ($installedAlreadyFile)"
        }
    CATCH
        {
        Write-EventLog -LogName Application -Source $eventLogSource -EntryType Error -EventID 911 -Message "Failed to remove the existing app version file.  App installation will continue, but there may be duplicate version files present.`nAppFolderName: $appFolderName`nStatusMsg: Failed to remove existing app version file"
        }
    }


# Copy the app folder to the Splunk Universal Forwarder apps directory
TRY
	{
	Copy-Item .\$appFolderName "$env:ProgramFiles\SplunkUniversalForwarder\etc\apps" -Recurse -Force -ErrorAction Stop
	$installedNow=$null=(($(Get-Item $env:ProgramFiles\SplunkUniversalForwarder\etc\apps\$appFolderName\default\*.version).Name) -replace ".version", "")
    IF ($installedNow -eq $null -OR $installedNow -eq "") {$installedNow = "<version file was not detected>"}
    Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -EventID 901 -Message "The app folder was successfully copied to the target directory.`nAppFolderName: $appFolderName`nStatusMsg: Successfully installed version $installedNow"
	$restartFlag = 1
	}
CATCH
	{
	Write-EventLog -LogName Application -Source $eventLogSource -EntryType Error -EventID 902 -Message "The app folder failed to copy to the target directory.`nAppFolderName: $appFolderName`nStatusMsg: Failed to install"
	$restartFlag = 0
	}

# If flagged, restart the Splunk Forwarder for the new inputs to become effective
IF ($restartFlag -eq 1)
	{
	TRY
		{
		Start-Sleep -Seconds 2
        Restart-Service SplunkForwarder -ErrorAction Stop
		Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -EventID 903 -Message "The Splunk Universal Forwarder was successfully restarted in order for the configuration from the newly installed app to take effect.`nAppFolderName: $appFolderName`nStatusMsg: Successfully restarted the Splunk Universal Forwarder"
		}
	CATCH
		{
		Write-EventLog -LogName Application -Source $eventLogSource -EntryType Error -EventID 904 -Message "The Splunk Universal Forwarder failed to restart.  Configuration from the newly installed app is not in effect.`nAppFolderName: $appFolderName`nStatusMsg: Failed to restart the Splunk Universal Forwarder"
		}
	}
