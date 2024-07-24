[中文](./Analysis_of_Microsoft's_CrowdStrike_Incident_Remediation_Script-CN.md)|[English](./Analysis_of_Microsoft's_CrowdStrike_Incident_Remediation_Script-EN.md)
Translate using a translation engine, the initial language of this document is Chinese

# Analysis of Microsoft's CrowdStrike incident fix scripts
## introduction

In the daily maintenance and deployment of the system, some challenging tasks are often encountered, such as recovering BitLocker encrypted volumes, conducting large-scale deployment of the Windows operating system, etc. In order to accomplish these tasks, we usually need to utilize some advanced techniques and tools. In the recent CrowdStrike issue, Microsoft provided a PowerShell script for recovery to help simplify the recovery process. [New Recovery Tool to help with CrowdStrike issue impacting Windows endpoints](https://techcommunity.microsoft.com/t5/intune-customer-success/new-recovery-tool-to-help-with-crowdstrike-issue-impacting/ba-p/4196959)
。 

Scripts are available from [the signed Microsoft Recovery Tool](https://go.microsoft.com/fwlink/?linkid=2280386), provided by Intune_Support_Team. This script uses a variety of modern tools and techniques, and the script itself is not just designed for the CrowdStrike issue, but also for other work.
Consider that there are customers who want to know what specific things Microsoft did in this script to determine whether to use this automated way to fix it. I decided to do an in-depth analysis of this script to help you better understand the technical details and how it works. 


 

## Background
### Windows Preinstallation Environment (WinPE)
First of all, we need to understand a concept called WinPE, which may be better understood by changing it to a popular word`"启动U盘"`

**WinPE, **or Windows Pre-Installation Environment, is a lightweight operating system designed for system installation, maintenance, and recovery. It's based on the Windows kernel, but removes most of the unnecessary components, allowing it to get up and running quickly with specific tasks. WinPE is very versatile:

- **Disk Management**: Create, format, and partition hard drives. 
- **System deployment**: Support automated image capture and application. 
- **Troubleshooting**: Run command-line tools and custom scripts to fix system issues. 


### Windows Assessment and Deployment Kit (ADK)
Another concept is called ADK
**The Windows ADK** is a suite of tools for evaluating, customizing, and deploying Windows operating system images. The ADK consists of multiple components, each with unique capabilities, such as:

- **Deployment Tools**：Generate, capture, and apply Windows images (. wim files)。 
- **Windows Performance Toolkit**：Analyze system performance。 
- **Application Compatibility Toolkit**：Evaluate and address application compatibility issues。 

### Customize the advanced features of WinPE

By combining** ADK **and** WinPE, **many advanced features can be achieved. Here are some specific examples:

1. **Embedding Drivers and Packages**:
   - Add hardware-specific support to provide a common recovery solution for different devices.
   - Import WMI packages to allow for more complex scripting and management operations.

2. **Network Features**:
   - WinPE can be loaded with network drivers for remote access and management.

3. **Secure Boot & Encryption**:
   - Enable Secure Startup module to support BitLocker encryption and decryption operations。

4. **Automated Deployment**:
   - Custom scripts and tool integrations to support unattended installation and batch deployment.

5. **Some customized boot USB flash drives**:
   - Run the system diagnostic tool to repair system files and registry.
   - Reset the password and fix the startup issue.
   - Do not invade the actual system, and directly perform certain operations.
   - Format the system, install the system
   - Recover data

These technical methods are widely used in various enterprise IT management scenarios, providing great convenience and flexibility for system engineers and administrators. However, the process of customizing WinPE itself is not simple, and it requires an in-depth understanding of the Windows system and related tools in order to maximize its effectiveness.

## Script analysis
This script is used to automatically create a bootable USB device or ISO containing a repair tool on a Windows PC, to use the recovery key, to configure and mount the WinPE image by downloading and installing the Windows ADK and its WinPE add-on, to generate a recovery batch file, and finally to make a medium for system repair and safe mode boot.

The crux of the whole script is that it automates the process of generating PEs, as well as the process of unlocking Bitlocker with the key. Although this is a little more complicated for administrators, it can greatly simplify the operation process and improve the work efficiency for front-line engineers.

### Download and install the ADK
Let's take the latest July 23rd `MsftRecoveryToolForCSv31.ps1` .
First, the script tries to check to initialize some variables, as well as check if there are administrator privileges, and if not, try to elevate privileges. Check the installation of winpe and adk at the same time, and try to download the installation if it doesn't. It should be noted here that the script is used`Invoke-WebRequest` to download the file, and at the same time, the detection logic is slightly problematic, but it is simply based on whether a file exists to determine whether it is installed, in fact, this file may be a residual file, which does not necessarily mean that the installation is successful. 

For example, the following code snippet is used to check if the ADK is installed successfully, which can be determined by checking if`Windows Deployment Tools` the software is available. But that's not the point of the script, and we can circumvent this problem by preparing a clean machine. 
```powershell
$installedSoftware = Get-WmiObject -Class Win32_Product
$adkInstalled = $installedSoftware| Where-Object { 
    $_.Name -eq "Windows Deployment Tools" -and $_.Version -eq "10.1.26100.1" 
}
```

### Provides options and initializes the environment
This script is primarily used to prompt the administrator to select a recovery option and initialize the deployment tool environment variables before running WinPE (Windows pre-installed environment). The specific steps are as follows:

1. **Recovery options available**:
   - Outputs descriptions of the two recovery options:  
     - Option 1: Boot to WinPE for repair, if the system disk is encrypted by BitLocker, you need to enter the BitLocker recovery key.
     - Option 2: Boot into WinPE to configure safe mode and run the repair command once you enter safe mode, in which case it is unlikely that you will need to enter the BitLocker recovery key.
   - The user is asked which recovery option to choose and the selection is stored in a variable`$winPEScriptOption`. 

2. **Initialize the deployment tool environment**:
   - Prompt: The initialization of the deployment tool environment has begun.
   - Set environment variables using Deployment Tools:
     - Run a batch file that comes with the ADK `DandISetEnv.bat`to get the required environment variables. 
     - Add these environment variables one by one to the current PowerShell environment for them to take effect.

 
```powershell

#
# Let admin pick safe boot or bitlocker key option before mounting the image
#

Write-Host ""
Write-Host "This script offers two options for recovering impacted devices:"
Write-Host "1. Boot to WinPE to remediate the issue. It requires entering bitlocker recovery key if system disk is bitlocker encrypted."
Write-Host "2. Boot to WinPE configure safe mode and run repair command after entering safe mode. This option is less likely to require bitlocker recovery key if system disk is bitlocker encrypted."
Write-Host ""
$winPEScriptOption = Read-Host "Which of the two options would you like to include in the WinPE image ? [1] or [2]"

# 
# Run the Deployment tools to set environment variables
#
Write-Host "Initializing Deployment Toolkit Environment..."

# Fetch the correct variables to be added.
$envVars = cmd.exe /c """$ADKInstallLocation\Assessment and Deployment Kit\Deployment Tools\DandISetEnv.bat"" && set" | Out-String

$envVars -split "`r`n" | ForEach-Object {
    if ($_ -match "^(.*?)=(.*)$")
    {
        # Update the current execution environment
        [System.Environment]::SetEnvironmentVariable($matches[1], $matches[2], [System.EnvironmentVariableTarget]::Process)
    }
}
```

### Use DISM to mount the WinPE image
The Deployment Imaging Service and Management Tool (DISM) is a command-line tool for deploying, managing, and servicing Windows images. This tool is typically used by system administrators to create and maintain Windows Pre-Installation Environments (WinPE), Windows Recovery Environments, and custom Windows operating system images. In this script, DISM is used to mount the WinPE image for subsequent modification and configuration.
- Make sure that the directory of the mount point of the WinPE image exists.
- Make sure you have a copy of the WinPE image in your working directory.
- Use the DISM tool to mount the WinPE image to the specified directory.
- Delete old batch files that may exist to avoid interfering with subsequent operations.
These steps are usually the initial preparation required before configuring or modifying a WinPE image.

```powershell
#
# Use Dism to mount the WinPE image
#
Write-Host "Mounting WinPE image..."

if (!(Test-Path -Path $WinPEMountLocation))
{
    $mtDirRes = New-Item -Path $WinPEMountLocation -ItemType Directory
}
if (!(Test-Path -Path $WorkingWinPELocation))
{
    $wkDirRes = Copy-Item -Path "$ADKWinPELocation" -Destination "$WorkingWinPELocation" -Force
}

$mtResult = Mount-WindowsImage -ImagePath "$ADKWinPELocation" -Index 1 -Path "$WinPEMountLocation"

# Repair cmd file is located in the root folder of the media
$RepairCmdFile = "$ADKWinPEMediaLocation\repair.cmd"

# Remove any existing batch files
if (Test-Path "$WinPEMountLocation\CSRemediationScript.bat")
{
    Remove-Item "$WinPEMountLocation\CSRemediationScript.bat"
}

if (Test-Path "$RepairCmdFile")
{
    Remove-Item "$RepairCmdFile"
}

```


### Generate a recovery batch file

This PowerShell script generates two different batch files based on the recovery option selected by the user, which is used to boot the system into safe mode and perform repair actions in safe mode. This approach simplifies some of the common tasks in the system recovery process, such as safe mode configuration, file deletion, and boot settings recovery, in an automated manner. Using simple logic here,`out-file` write commands to batch files via commands and then run those batch files in WinPE. While the code is PowerShell, a batch file is actually generated. 

This code is the core code, but interestingly it uses batch processing for the main logic implementation. In fact, if you load PowerShell packages in Winpe, you also support PowerShell logic, but batch processing is chosen here, probably because batch processing is simpler, more stable, and more versatile. For developers, however, batch processing is older and requires more knowledge and technology to modify, while PowerShell is more modern and easier to understand. But anyway, it's just an option, different people have different options, and batch processing is chosen here.

These codes are used to generate two batch files (`.bat` and  ) `.cmd`for different recovery options using PowerShell scripts. Specifically, based on the recovery option selected by the user (determined by the variable `$winPEScriptOption` ), the corresponding batch file is generated to configure and recover the system. 

Generate the first batch file(s`CSRemediationScript.bat`) to configure safe mode boot. If the recovery option is selected`'2'`, the script generates a batch file that is used to configure the system to boot in safe mode. Create and write CSRemediationScript.bat file to the mounted WinPE image pathThis batch file has a series of operations, including:
- Prompts and warnings.
- Use `bcdedit` the command to configure the system to boot in safe mode. 
- Check whether the command was successful or not, and display different information depending on the situation.

A second batch file(s`Repair.cmd`) is generated to remove the affected files and restore the normal boot configuration. The script then generates another batch file that can be used to perform repair operations after booting in safe mode

The batch file includes:
- Some tips and warnings.
- Delete the affected files.
- Restore the normal boot configuration.
- Reboot the system.

If the recovery option is not selected`'2'`, another batch file () `CSRemediationScript.bat`is generated, and if the recovery option is not selected `'2'` , the script generates a different batch file for another repair method

This batch file mainly includes:
- Check the status of BitLocker.
- The user is prompted to take the next step based on the return code.
- Allows the user to enter an alternative drive letter and try again.
- Try unlocking the drive and deleting the affected files.


Essentially, the PowerShell script generates two different batch files based on the recovery option selected by the user to boot the system into safe mode and perform remediation actions in safe mode. 

These 3 cmd commands are roughly as follows, which are very easy to obtain in themselves, and you only need to execute the code once to get these files in the PE directory.
```cmd
 
@echo off
echo This tool will configure this machine to boot in safe mode.
echo WARNING: In some cases you may need to enter a BitLocker recovery key after running.
pause
echo.
bcdedit /set {default} safeboot network
echo.
IF %ERRORLEVEL% EQU 0 (
     echo .................................................
     echo Your PC is configured to boot to Safe Mode now.   
     echo .................................................
     echo If you manually changed the boot order on the device, restore the boot order to the previous state before rebooting. If BitLocker is enabled, make sure to remove the USB or bootable recovery device attached to prevent BitLocker recovery.
     echo .................................................
echo.
) ELSE (
     echo Could not configure safe mode on this system.
   )
echo.
echo Upon reboot, run repair.cmd from the root of the media/USB drive to remove impacted files and disable safe mode.
echo.
pause
exit 0



@echo on
@setlocal enabledelayedexpansion
 
@set drive=C:
:tryagain
@echo Using drive %drive%
@echo.
@echo If your device is BitLocker encrypted use your phone to log on to https://aka.ms/aadrecoverykey. Log on with your Email ID and domain account password to find the BitLocker recovery key associated with your device.
@echo.
 
@rem If no key protectors are found, this command will return -1 and display "ERROR: No key protectors found.". This error can be ignored.
manage-bde.exe -protectors %drive% -get -Type RecoveryPassword
 
@IF NOT [%ERRORLEVEL%] == [0] @IF NOT [%ERRORLEVEL%] == [-1] (
    @echo. ERROR: Failed with return code %ERRORLEVEL%
    @echo.
    set /p continue="Would you like to [C]ontinue or [T]ry another drive? [C/T] "
    @if [!continue!] == [C] goto :next
 
    @set /p drive="Enter alternate drive letter to try (e.g. Z:): "
    @goto :tryagain
)
 
:next
@echo.
 
@set /p reckey="Enter recovery key for this drive if required: "
@IF NOT [%reckey%] == [] (
    @echo Unlocking drive %drive%
    manage-bde.exe -unlock %drive% -recoverypassword %reckey%
    IF NOT [!ERRORLEVEL!] == [0] @IF NOT [!ERRORLEVEL!] == [-1] (
        @echo. ERROR: Failed with return code %ERRORLEVEL%
        @echo.
        set /p continue="Would you like to [C]ontinue or [T]ry another drive? [C/T] "
        @if [!continue!] == [C] goto :next2
 
        @set /p drive="Enter alternate drive letter to try (e.g. Z:): "
        @goto :tryagain
    )    
)
:next2
@set targetfiles=%drive%\Windows\System32\drivers\CrowdStrike\C-00000291*.sys
@if exist %targetfiles% (
    @echo. Target file^(s^) %targetfiles% detected:
    @echo.
    @dir %targetfiles%
    @echo. Removing file^(s^)...
    del /f %targetfiles%
    @echo Done performing cleanup operation.
) else (
    @echo Target files were not detected.
)
:end
@echo.
@pause
@exit 0









```


```powershell
#
# Generate batch files based on the earlier selection of the recovery option
#
if ($winPEScriptOption.ToUpperInvariant() -eq '2')
{
    #
    # Generate batch file
    #
    "@echo off" | Out-File -FilePath "$WinPEMountLocation\CSRemediationScript.bat" -Append -Encoding ascii
    "echo This tool will configure this machine to boot in safe mode." | Out-File -FilePath "$WinPEMountLocation\CSRemediationScript.bat" -Append -Encoding ascii
    "echo WARNING: In some cases you may need to enter a BitLocker recovery key after running." | Out-File -FilePath "$WinPEMountLocation\CSRemediationScript.bat" -Force -Append -Encoding ascii
    "pause" | Out-File -FilePath "$WinPEMountLocation\CSRemediationScript.bat" -Force -Append -Encoding ascii
    "echo." | Out-File -FilePath "$WinPEMountLocation\CSRemediationScript.bat" -Force -Append -Encoding ascii
    "bcdedit /set {default} safeboot network" | Out-File -FilePath "$WinPEMountLocation\CSRemediationScript.bat" -Force -Append -Encoding ascii
    "echo." | Out-File -FilePath "$WinPEMountLocation\CSRemediationScript.bat" -Force -Append -Encoding ascii
    "IF %ERRORLEVEL% EQU 0 (" | Out-File -FilePath "$WinPEMountLocation\CSRemediationScript.bat" -Force -Append -Encoding ascii
    "     echo ................................................." | Out-File -FilePath "$WinPEMountLocation\CSRemediationScript.bat" -Force -Append -Encoding ascii
    "     echo Your PC is configured to boot to Safe Mode now.   " | Out-File -FilePath "$WinPEMountLocation\CSRemediationScript.bat" -Force -Append -Encoding ascii
    "     echo ................................................." | Out-File -FilePath "$WinPEMountLocation\CSRemediationScript.bat" -Force -Append -Encoding ascii
    "     echo If you manually changed the boot order on the device, restore the boot order to the previous state before rebooting. If BitLocker is enabled, make sure to remove the USB or bootable recovery device attached to prevent BitLocker recovery." | Out-File -FilePath "$WinPEMountLocation\CSRemediationScript.bat" -Force -Append -Encoding ascii
    "     echo ................................................." | Out-File -FilePath "$WinPEMountLocation\CSRemediationScript.bat" -Force -Append -Encoding ascii
    "echo." | Out-File -FilePath "$WinPEMountLocation\CSRemediationScript.bat" -Force -Append -Encoding ascii
    ") ELSE (" | Out-File -FilePath "$WinPEMountLocation\CSRemediationScript.bat" -Force -Append -Encoding ascii
    "     echo Could not configure safe mode on this system." | Out-File -FilePath "$WinPEMountLocation\CSRemediationScript.bat" -Force -Append -Encoding ascii
    "   )" | Out-File -FilePath "$WinPEMountLocation\CSRemediationScript.bat" -Force -Append -Encoding ascii
    "echo." | Out-File -FilePath "$WinPEMountLocation\CSRemediationScript.bat" -Force -Append -Encoding ascii
    "echo Upon reboot, run repair.cmd from the root of the media/USB drive to remove impacted files and disable safe mode." | Out-File -FilePath "$WinPEMountLocation\CSRemediationScript.bat" -Force -Append -Encoding ascii
    "echo." | Out-File -FilePath "$WinPEMountLocation\CSRemediationScript.bat" -Force -Append -Encoding ascii
    "pause" | Out-File -FilePath "$WinPEMountLocation\CSRemediationScript.bat" -Force -Append -Encoding ascii
    "exit 0" | Out-File -FilePath "$WinPEMountLocation\CSRemediationScript.bat" -Append -Encoding ascii

    #
    # Generate Repair.cmd
    #
    "@echo off" | Out-File -FilePath "$RepairCmdFile" -Append -Encoding ascii
    "echo This tool will remove impacted files and restore normal boot configuration." | Out-File -FilePath "$RepairCmdFile" -Append -Encoding ascii
    "echo." | Out-File -FilePath "$RepairCmdFile" -Append -Encoding ascii
    "echo WARNING: You may need BitLocker recovery key in some cases."  | Out-File -FilePath "$RepairCmdFile" -Append -Encoding ascii
    "echo WARNING: This script must be run in an elevated command prompt." | Out-File -FilePath "$RepairCmdFile" -Append -Encoding ascii
    "echo." | Out-File -FilePath "$RepairCmdFile" -Append -Encoding ascii
    "pause" | Out-File -FilePath "$RepairCmdFile" -Append -Encoding ascii
    "echo Removing impacted files..."  | Out-File -FilePath "$RepairCmdFile" -Append -Encoding ascii
    "del %SystemRoot%\System32\drivers\CrowdStrike\C-00000291*.sys" | Out-File -FilePath "$RepairCmdFile" -Append -Encoding ascii
    "echo Restoring normal boot flow..."  | Out-File -FilePath "$RepairCmdFile" -Append -Encoding ascii
    "bcdedit /deletevalue {current} safeboot" | Out-File -FilePath "$RepairCmdFile" -Append -Encoding ascii
    "echo Success. System will now reboot." | Out-File -FilePath "$RepairCmdFile" -Append -Encoding ascii
    "pause" | Out-File -FilePath "$RepairCmdFile" -Append -Encoding ascii
    "shutdown -r -t 00" | Out-File -FilePath "$RepairCmdFile" -Append -Encoding ascii
}
else 
{
    #
    # Generate batch file
    #
    "@echo on" | Out-File -FilePath "$WinPEMountLocation\CSRemediationScript.bat" -Force -Append -Encoding ascii
    "@setlocal enabledelayedexpansion" | Out-File -FilePath "$WinPEMountLocation\CSRemediationScript.bat" -Force -Append -Encoding ascii
    " " | Out-File -FilePath "$WinPEMountLocation\CSRemediationScript.bat" -Force -Append -Encoding ascii
    "@set drive=C:" | Out-File -FilePath "$WinPEMountLocation\CSRemediationScript.bat" -Force -Append -Encoding ascii
    ":tryagain" | Out-File -FilePath "$WinPEMountLocation\CSRemediationScript.bat" -Force -Append -Encoding ascii
    "@echo Using drive %drive%" | Out-File -FilePath "$WinPEMountLocation\CSRemediationScript.bat" -Force -Append -Encoding ascii
    "@echo." | Out-File -FilePath "$WinPEMountLocation\CSRemediationScript.bat" -Force -Append -Encoding ascii
    "@echo If your device is BitLocker encrypted use your phone to log on to https://aka.ms/aadrecoverykey. Log on with your Email ID and domain account password to find the BitLocker recovery key associated with your device." | Out-File -FilePath "$WinPEMountLocation\CSRemediationScript.bat" -Force -Append -Encoding ascii
    "@echo." | Out-File -FilePath "$WinPEMountLocation\CSRemediationScript.bat" -Force -Append -Encoding ascii
    " " | Out-File -FilePath "$WinPEMountLocation\CSRemediationScript.bat" -Force -Append -Encoding ascii
    "@rem If no key protectors are found, this command will return -1 and display ""ERROR: No key protectors found."". This error can be ignored." | Out-File -FilePath "$WinPEMountLocation\CSRemediationScript.bat" -Force -Append -Encoding ascii
    "manage-bde.exe -protectors %drive% -get -Type RecoveryPassword" | Out-File -FilePath "$WinPEMountLocation\CSRemediationScript.bat" -Force -Append -Encoding ascii
    " " | Out-File -FilePath "$WinPEMountLocation\CSRemediationScript.bat" -Force -Append -Encoding ascii
    "@IF NOT [%ERRORLEVEL%] == [0] @IF NOT [%ERRORLEVEL%] == [-1] (" | Out-File -FilePath "$WinPEMountLocation\CSRemediationScript.bat" -Force -Append -Encoding ascii
    "    @echo. ERROR: Failed with return code %ERRORLEVEL%" | Out-File -FilePath "$WinPEMountLocation\CSRemediationScript.bat" -Force -Append -Encoding ascii
    "    @echo." | Out-File -FilePath "$WinPEMountLocation\CSRemediationScript.bat" -Force -Append -Encoding ascii
    "    set /p continue=""Would you like to [C]ontinue or [T]ry another drive? [C/T] """ | Out-File -FilePath "$WinPEMountLocation\CSRemediationScript.bat" -Force -Append -Encoding ascii
    "    @if [!continue!] == [C] goto :next" | Out-File -FilePath "$WinPEMountLocation\CSRemediationScript.bat" -Force -Append -Encoding ascii
    " " | Out-File -FilePath "$WinPEMountLocation\CSRemediationScript.bat" -Force -Append -Encoding ascii
    "    @set /p drive=""Enter alternate drive letter to try (e.g. Z:): """ | Out-File -FilePath "$WinPEMountLocation\CSRemediationScript.bat" -Force -Append -Encoding ascii
    "    @goto :tryagain" | Out-File -FilePath "$WinPEMountLocation\CSRemediationScript.bat" -Force -Append -Encoding ascii
    ")" | Out-File -FilePath "$WinPEMountLocation\CSRemediationScript.bat" -Force -Append -Encoding ascii
    " " | Out-File -FilePath "$WinPEMountLocation\CSRemediationScript.bat" -Force -Append -Encoding ascii
    ":next" | Out-File -FilePath "$WinPEMountLocation\CSRemediationScript.bat" -Force -Append -Encoding ascii
    "@echo." | Out-File -FilePath "$WinPEMountLocation\CSRemediationScript.bat" -Force -Append -Encoding ascii
    " " | Out-File -FilePath "$WinPEMountLocation\CSRemediationScript.bat" -Force -Append -Encoding ascii
    "@set /p reckey=""Enter recovery key for this drive if required: """ | Out-File -FilePath "$WinPEMountLocation\CSRemediationScript.bat" -Force -Append -Encoding ascii
    "@IF NOT [%reckey%] == [] (" | Out-File -FilePath "$WinPEMountLocation\CSRemediationScript.bat" -Force -Append -Encoding ascii
    "    @echo Unlocking drive %drive%" | Out-File -FilePath "$WinPEMountLocation\CSRemediationScript.bat" -Force -Append -Encoding ascii
    "    manage-bde.exe -unlock %drive% -recoverypassword %reckey%" | Out-File -FilePath "$WinPEMountLocation\CSRemediationScript.bat" -Force -Append -Encoding ascii
    "    IF NOT [!ERRORLEVEL!] == [0] @IF NOT [!ERRORLEVEL!] == [-1] (" | Out-File -FilePath "$WinPEMountLocation\CSRemediationScript.bat" -Force -Append -Encoding ascii
    "        @echo. ERROR: Failed with return code %ERRORLEVEL%" | Out-File -FilePath "$WinPEMountLocation\CSRemediationScript.bat" -Force -Append -Encoding ascii
    "        @echo." | Out-File -FilePath "$WinPEMountLocation\CSRemediationScript.bat" -Force -Append -Encoding ascii
    "        set /p continue=""Would you like to [C]ontinue or [T]ry another drive? [C/T] """ | Out-File -FilePath "$WinPEMountLocation\CSRemediationScript.bat" -Force -Append -Encoding ascii
    "        @if [!continue!] == [C] goto :next2" | Out-File -FilePath "$WinPEMountLocation\CSRemediationScript.bat" -Force -Append -Encoding ascii
    " " | Out-File -FilePath "$WinPEMountLocation\CSRemediationScript.bat" -Force -Append -Encoding ascii
    "        @set /p drive=""Enter alternate drive letter to try (e.g. Z:): """ | Out-File -FilePath "$WinPEMountLocation\CSRemediationScript.bat" -Force -Append -Encoding ascii
    "        @goto :tryagain" | Out-File -FilePath "$WinPEMountLocation\CSRemediationScript.bat" -Force -Append -Encoding ascii
    "    )    " | Out-File -FilePath "$WinPEMountLocation\CSRemediationScript.bat" -Force -Append -Encoding ascii
    ")" | Out-File -FilePath "$WinPEMountLocation\CSRemediationScript.bat" -Force -Append -Encoding ascii
    ":next2" | Out-File -FilePath "$WinPEMountLocation\CSRemediationScript.bat" -Force -Append -Encoding ascii
    "@set targetfiles=%drive%\Windows\System32\drivers\CrowdStrike\C-00000291*.sys" | Out-File -FilePath "$WinPEMountLocation\CSRemediationScript.bat" -Force -Append -Encoding ascii
    "@if exist %targetfiles% (" | Out-File -FilePath "$WinPEMountLocation\CSRemediationScript.bat" -Force -Append -Encoding ascii
    "    @echo. Target file^(s^) %targetfiles% detected:" | Out-File -FilePath "$WinPEMountLocation\CSRemediationScript.bat" -Force -Append -Encoding ascii
    "    @echo." | Out-File -FilePath "$WinPEMountLocation\CSRemediationScript.bat" -Force -Append -Encoding ascii
    "    @dir %targetfiles%" | Out-File -FilePath "$WinPEMountLocation\CSRemediationScript.bat" -Force -Append -Encoding ascii
    "    @echo. Removing file^(s^)..." | Out-File -FilePath "$WinPEMountLocation\CSRemediationScript.bat" -Force -Append -Encoding ascii
    "    del /f %targetfiles%" | Out-File -FilePath "$WinPEMountLocation\CSRemediationScript.bat" -Force -Append -Encoding ascii
    "    @echo Done performing cleanup operation." | Out-File -FilePath "$WinPEMountLocation\CSRemediationScript.bat" -Force -Append -Encoding ascii
    ") else (" | Out-File -FilePath "$WinPEMountLocation\CSRemediationScript.bat" -Force -Append -Encoding ascii
    "    @echo Target files were not detected." | Out-File -FilePath "$WinPEMountLocation\CSRemediationScript.bat" -Force -Append -Encoding ascii
    ")" | Out-File -FilePath "$WinPEMountLocation\CSRemediationScript.bat" -Force -Append -Encoding ascii
    ":end" | Out-File -FilePath "$WinPEMountLocation\CSRemediationScript.bat" -Force -Append -Encoding ascii
    "@echo." | Out-File -FilePath "$WinPEMountLocation\CSRemediationScript.bat" -Force -Append -Encoding ascii
    "@pause" | Out-File -FilePath "$WinPEMountLocation\CSRemediationScript.bat" -Force -Append -Encoding ascii
    "@exit 0" | Out-File -FilePath "$WinPEMountLocation\CSRemediationScript.bat" -Force -Append -Encoding ascii
}

```

### Add packages and drivers to the PE
`winpeshl.ini `is a Windows Preinstallation Environment (Windows PE)-specific configuration file that specifies applications that run automatically when WinPE starts. To write a `winpeshl.ini` file, you need to understand some basic configuration rules, such as  the section `[LaunchApps]` for specifying the application to be launched. This script is used to add the necessary packages and drivers to the WinPE image so that it will function properly when WinPE starts. Specifically, this script will:

- The winpeshl.ini file is automatically generated so that the specified recovery script automatically runs when WinPE starts.
- Add the necessary packages, such as WMI and Secure Startup, as well as the corresponding localization packages.
- Optionally, additional drivers can be added to the WinPE image based on user input.

```powershell
# Generate WinPEShl.ini file to autolaunch recovery script
#
"[LaunchApps]" | Out-File -FilePath "$WinPEMountLocation\Windows\system32\winpeshl.ini" -Force -Encoding ascii
"%SYSTEMDRIVE%\Windows\system32\cmd.exe /k %SYSTEMDRIVE%\CSRemediationScript.bat" | Out-File -FilePath "$WinPEMountLocation\Windows\system32\winpeshl.ini" -Append -Encoding ascii

# Add necessary packages
Write-Host "Adding necessary packages..."

# WinPE-WMI.cab
$pkgWmiResult = Add-WindowsPackage -Path "$WinPEMountLocation" -PackagePath "$ADKInstallLocation\Assessment and Deployment Kit\Windows Preinstallation Environment\amd64\WinPE_OCs\WinPE-WMI.cab"
$pkgWmiLngResult = Add-WindowsPackage -Path "$WinPEMountLocation" -PackagePath "$ADKInstallLocation\Assessment and Deployment Kit\Windows Preinstallation Environment\amd64\WinPE_OCs\en-us\WinPE-WMI_en-us.cab"

# WinPE-SecureStartup.cab
$pkgStartResult=Add-WindowsPackage -Path "$WinPEMountLocation" -PackagePath "$ADKInstallLocation\Assessment and Deployment Kit\Windows Preinstallation Environment\amd64\WinPE_OCs\WinPE-SecureStartup.cab"
$pkgStartLngResult = Add-WindowsPackage -Path "$WinPEMountLocation" -PackagePath "$ADKInstallLocation\Assessment and Deployment Kit\Windows Preinstallation Environment\amd64\WinPE_OCs\en-us\WinPE-SecureStartup_en-us.cab"

#
# Optionally add drivers to the WinPE image
#
$confirmation = Read-Host "Do you need to add drivers to the WinPE image ? [Y]es or [N]o"
if ($confirmation.ToUpperInvariant() -eq 'Y')
{
    $driverPath = Read-Host "Specify the folder that contains subfolders with driver (.ini) files or press Enter to skip"

    if ($driverPath -ne "")
    {
        Write-Host "Adding drivers..."
        Add-WindowsDriver -Path "$WinPEMountLocation" -Driver "$driverPath" -Recurse
    }
}
```


### The last part
These PowerShell scripts are used to create and manipulate custom Windows Pre-Installation Environment (WinPE) images, and generate ISO files or write them to USB drives at the user's choice

There are two main commands here:

- ` CopyPE amd64 "<WinPEStagingLocation>"`
- This command is used to copy the WinPE files to a specified directory, which is the directory used to make the boot disk.

- ` MakeWinPEMedia /ISO "<WinPEStagingLocation>" "<RecoveryImageLocation>"`
- This command is used to create a WinPE ISO file, which can be used to make a boot disk, which can be used to boot the system and then perform repair operations.

- **`CopyPE`** Prepare the WinPE media environment, which does not generate an ISO file, but is necessary as a preceding ISO generation.
- **`MakeWinPEMedia /ISO`** is the command that actually generates the ISO file, and it's called after the first step is complete.


If the user chooses to create a USB key, it goes to the appropriate code block, otherwise the user is informed of the location of the ISO file.

- Obtain and verify the drive letter of the USB drive.
- Verify that the USB drive is present and no larger than 32GB.
- Format the USB drive for a FAT32 file system.
- Mount the ISO file and copy its contents to a USB drive.
- Uninstall the ISO file, clean up the operation.

The detection disk here does not exceed 32GB, probably because 32GB is the maximum support of the fat32 file system. On Windows, formatting a FAT32 partition using a built-in tool, such as Disk Manager, is usually limited to less than 32 GB.

```powershell

#
# Unmount and commit WinPE image
#
Write-Host "Saving the changes to the WinPE image..."
$disImgResult = Dismount-WindowsImage -Path "$WinPEMountLocation" -Save

#
# Creates working directories for WinPE media creation
#
$WinPEStagingLocation = [System.Environment]::ExpandEnvironmentVariables("%TEMP%\WinPEStagingLocation")

if ((Test-Path -Path $WinPEStagingLocation))
{
    $WinPeRemResult = Remove-Item -Path $WinPEStagingLocation -Force -Recurse
}

[System.Environment]::SetEnvironmentVariable("WinPERoot", "$ADKInstallLocation\Assessment and Deployment Kit\Windows Preinstallation Environment")
[System.Environment]::SetEnvironmentVariable("OSCDImgRoot", "$ADKInstallLocation\Assessment and Deployment Kit\Deployment Tools\AMD64\Oscdimg")

$cmdArgs = "amd64 " + "`"$WinPEStagingLocation`""
Start-Process -FilePath $CopyPEPath -ArgumentList $cmdArgs -Wait -NoNewWindow

Write-Host "Creating ISO..."

# Create the ISO
if (Test-Path -Path $RecoveryImageLocation)
{
    Remove-Item -Path $RecoveryImageLocation -Force
}

$CmdArgs = "/ISO " + "`"$WinPEStagingLocation`" `"$RecoveryImageLocation`""
Start-Process -FilePath $MakeWinPEMediaPath -ArgumentList $cmdArgs -Wait -NoNewWindow

#
# Prompt if iso or USB is needed
#
$isUsb = Read-Host "Do you need an ISO [1] or a USB [2] ?"
if ($isUsb.ToUpperInvariant() -eq '2')
{    
    #
    # Make USB Key
    #

    $USBDrive = Read-Host "What is the drive letter of your USB Key?"

    if ($USBDrive.Length -lt 1)
    {
        Write-Host "ERROR: Invalid drive letter"
        Exit
    }

    if ($USBDrive.Length -eq 1)
    {
        $USBDrive = -join ($USBDrive, ":")
    }

    if (!(Test-Path $USBDrive))
    {
        Write-Host "ERROR: Drive not found"
        Exit
    }

    $usbVolume = Get-Volume -DriveLetter $USBDrive[0]
    if (($usbVolume.Size) -gt 32GB)
    {
        Write-Host "ERROR: USB drives larger than 32GB are not supported. Please shrink the drive partitions and re-run the script."
        Exit
    }

    Format-Volume -DriveLetter $USBDrive[0] -FileSystem FAT32

    Write-Host "Making USB media..."

    # Mount the ISO
    $mountVolume = Mount-DiskImage -ImagePath "$RecoveryImageLocation" -PassThru
    $mountLetter = ($mountVolume | Get-Volume).DriveLetter + ":\*"

    Write-Host "Copying contents to the USB drive..."
    Copy-Item -Path $mountLetter -Destination "$USBDrive\" -Recurse

    Write-Host "Cleaning up..."
    $dismountResult = Dismount-DiskImage -ImagePath "$RecoveryImageLocation"

    Write-Host "DONE: You can now boot from the USB key."

}
else {
    Write-Host "ISO is available here: $RecoveryImageLocation"
}

if (Test-Path -Path $WinPEStagingLocation)
{
    $remStgResult = Remove-Item -Path $WinPEStagingLocation -Force -Recurse
}

if (($isUsb -eq $true) -and (Test-Path -Path $RecoveryImageLocation))
{
    $remImgResult = Remove-Item -Path $RecoveryImageLocation -Force
}

if (Test-Path -Path $WorkingLocation)
{
    $remWkResult = Remove-Item -Path $WorkingLocation -Force -Recurse
}


```
## summary
To sum up, the main purpose of this script is to generate a bootable USB device or ISO file containing a recovery tool through an automated process that will be used to simplify the system repair process.

Include:

1. **Download and install the ADK**: The script checks and downloads the necessary ADK components. 
2. **Provide options and initialize the environment**: Administrators can choose between two different recovery scenarios, and the script configures the environment based on the selection. 
3. **Mounting a WinPE Image Using DISM**: Use the DISM tool to mount a WinPE image for subsequent modifications. 
4. **Generate Recovery Batch File**: Generates a batch file for repair based on the user's choice. 
5. **Add packages and drivers to the PE: **Add the necessary packages and drivers to the WinPE image. 
6. **Create an ISO or USB key**: Eventually generate an ISO file containing the recovery tool or write it to a USB drive. 

Hopefully, this article will provide you with some help in dealing with system recovery issues, and ensure that the Microsoft script is successfully introduced in test and production environments, as well as provide theoretical support for modifying the script.
