# 对微软CrowdStrike事件修复脚本的分析
## 引子

在日常的系统维护和部署中，经常会遇到一些挑战性的任务，例如恢复BitLocker加密卷、进行大规模的Windows操作系统部署等。为了完成这些任务，我们通常需要利用一些高级技术和工具。在最近的CrowdStrike issue事件中，微软提供了一个恢复用的PowerShell脚本，帮助用户简化恢复过程。[New Recovery Tool to help with CrowdStrike issue impacting Windows endpoints](https://techcommunity.microsoft.com/t5/intune-customer-success/new-recovery-tool-to-help-with-crowdstrike-issue-impacting/ba-p/4196959)
。

脚本可从 [signed Microsoft Recovery Tool](https://go.microsoft.com/fwlink/?linkid=2280386)，由Intune_Support_Team提供。这段脚本用到了多种现代化的工具和技术，脚本本身不是单纯为CrowdStrike issue设计的，对其他工作它同样也有参考意义。
考虑到有客户希望了解微软在这个脚本中做了哪些具体的事情，以判定是否使用这种自动化的方式来进行修复。我决定对这个脚本进行深入分析，希望能够帮助大家更好地理解其中的技术细节和实现原理。


本文将带你深入了解其中的关键技术，包括Windows Preinstallation Environment (WinPE)、Windows Assessment and Deployment Kit (ADK) 以及如何通过定制WinPE来实现各种高级功能。

## 背景知识
### Windows Preinstallation Environment (WinPE)
首先我们需要了解一个概念叫做WinPE，换一个通俗的词可能更好理解`"启动U盘"`

**WinPE**，即Windows预安装环境，是一个轻量级的操作系统，专门用于系统安装、维护和恢复。它基于Windows内核，但删去了大部分不必要的组件，使其快速启动并运行一些特定任务。WinPE的用途非常广泛：

- **磁盘管理**：创建、格式化和分区硬盘。
- **系统部署**：支持自动化的图像捕获与应用。
- **故障排除**：运行命令行工具和自定义脚本以修复系统问题。


### Windows Assessment and Deployment Kit (ADK)
另外一个概念叫做ADK
**Windows ADK** 是一个包含多种工具的套件，用于评估、定制和部署Windows操作系统映像。ADK包含多个组件，每个组件都有独特的功能，如：

- **Deployment Tools**：生成、捕获和应用Windows镜像（.wim文件）。
- **Windows Performance Toolkit**：分析系统性能。
- **Application Compatibility Toolkit**：评估和处理应用程序兼容性问题。

### 定制WinPE的高级功能

通过结合使用**ADK**和**WinPE**，可以实现许多高级功能。以下是一些具体例子：

1. **嵌入驱动和包**：
   - 增加特定硬件的支持，为不同的设备提供通用恢复解决方案。
   - 导入WMI包，允许更复杂的脚本和管理操作。

2. **网络功能**：
   - WinPE可以加载网络驱动，用于远程访问和管理。

3. **安全启动和加密**：
   - 启用Secure Startup模块，支持BitLocker加密和解密操作。

4. **自动化部署**：
   - 自定义脚本和工具集成，支持无人值守安装和批量部署。

5. **某些定制化的启动U盘**：
   - 运行系统诊断工具，修复系统文件和注册表。
   - 重置密码，修复启动问题。
   - 不侵入实际系统，直接进行某些操作。
   - 格式化系统、安装系统
   - 恢复数据

这些技术方法，被广泛应用于各种企业IT管理场景中，为系统工程师和管理员提供了极大的便利和灵活性。然而本身定制WinPE的过程并不简单，需要对Windows系统和相关工具有深入的了解，才能发挥其最大的效用。

## 脚本分析
这个脚本用于在Windows PC上自动创建一个包含修复工具的可启动USB设备或者ISO，用来恢复密钥，通过下载和安装Windows ADK及其WinPE附加组件，配置并挂载WinPE映像，生成恢复批处理文件，并最终制作一个用于系统修复和安全模式启动的介质。

整个脚本的关键在于自动化了生成PE的过程，同时将密钥解锁Bitlocker的过程也自动化了。这虽然对于管理员而言稍微复杂一些，但对于一线工程师而言，可以大大简化操作流程，提高工作效率。

### 下载和安装ADK
我们以7月23日最新的 `MsftRecoveryToolForCSv31.ps1` 来进行介绍。
首先脚本尝试检查初始化一些变量，以及检查是否有管理员权限，如果没有则尝试提升权限。同时检查winpe和adk的安装情况，如果没有安装则尝试下载安装。这里需要注意，脚本中使用了`Invoke-WebRequest`来下载文件，同时，检测逻辑稍微有些问题，只是单纯根据某个文件是否存在来判断是否安装，实际上这个文件可能是残留文件，不一定代表安装成功。

例如下面的代码片段用来检查ADK是否安装成功，这通过检查是否有`Windows Deployment Tools`这个软件来判断。但这不是脚本的重点，我们可以通过准备一台干净的机器，来规避这个问题。
```powershell
$installedSoftware = Get-WmiObject -Class Win32_Product
$adkInstalled = $installedSoftware| Where-Object { 
    $_.Name -eq "Windows Deployment Tools" -and $_.Version -eq "10.1.26100.1" 
}
```

### 提供选项和初始化环境
这段脚本主要用于在运行WinPE（Windows 预安装环境）之前，提示管理员选择一种恢复选项，并初始化部署工具环境变量。具体步骤如下：

1. **提供恢复选项**：
   - 输出两种恢复选项的描述：  
     - 选项1：引导到WinPE进行修复，如果系统磁盘被BitLocker加密，需要输入BitLocker恢复密钥。
     - 选项2：引导到WinPE配置安全模式，并在进入安全模式后运行修复命令，这种情况下不太可能需要输入BitLocker恢复密钥。
   - 询问用户选择哪一种恢复选项，并将选择存储在变量`$winPEScriptOption`中。

2. **初始化部署工具环境**：
   - 提示已开始初始化部署工具环境。
   - 使用“Deployment Tools”设置环境变量：
     - 运行一个ADK自带的批处理文件`DandISetEnv.bat`来获取需要的环境变量。
     - 将这些环境变量逐一添加到当前的PowerShell环境中，使其生效。

 
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

### 使用DISM挂载WinPE映像
DISM（Deployment Imaging Service and Management Tool）是一个用于部署、管理和服务Windows镜像的命令行工具。这个工具通常用于系统管理员来创建及维护Windows预安装环境（WinPE）、Windows恢复环境，以及定制Windows操作系统映像。在这个脚本中，DISM被用来挂载WinPE映像，以便后续的修改和配置。
- 确保WinPE镜像挂载点目录存在。
- 确保工作目录中有一个WinPE镜像的副本。
- 使用DISM工具将WinPE镜像挂载到指定目录。
- 删除可能存在的旧批处理文件，以避免干扰后续操作。
这些步骤通常是在配置或修改WinPE映像之前所需的初始准备工作。

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


### 生成恢复批处理文件

这段 PowerShell 脚本会根据用户选择的恢复选项，生成两个不同的批处理文件用于引导系统进入安全模式，并在安全模式中执行修复操作。这种方法通过自动化的方式简化了系统恢复过程中的一些常见任务，如安全模式配置、文件删除和启动设置恢复。这里使用简单的逻辑，通过`out-file`命令将命令写入到批处理文件中，然后在WinPE中运行这些批处理文件。虽然代码是powershell，但实际上是生成了一个批处理文件。

这段代码是核心代码，但有意思的是使用了批处理来进行主要逻辑实现。事实上如果在winpe中，加载powershell的包，也支持powershell的逻辑，但是这里选择了批处理，可能是因为批处理更加简单，更加稳定，更加通用。然而对于开发人员而言，批处理更为古老，修改起来所需要的知识和技术更多，而powershell则更加现代化，更加容易理解。但是无论如何，这只是一种选择，不同的人有不同的选择，这里选择了批处理。

这些代码是使用PowerShell脚本来生成两个批处理文件（`.bat` 和 `.cmd`），用于不同的恢复选项。具体来说，根据用户选择的恢复选项（由变量 `$winPEScriptOption` 来决定），生成相应的批处理文件来配置和恢复系统。 

生成第一个批处理文件 (`CSRemediationScript.bat`) 用于配置安全模式启动。如果选择了恢复选项 `'2'`，脚本生成一个用于将系统配置为安全模式启动的批处理文件。在已挂载的WinPE映像路径下创建并写入CSRemediationScript.bat文件这个批处理文件有一系列操作，包括：
- 提示信息和警告。
- 使用 `bcdedit` 命令将系统配置为安全模式启动。
- 检查命令是否成功，并根据情况显示不同的信息。

生成第二个批处理文件 (`Repair.cmd`) 用于移除受影响的文件和恢复正常启动配置。接着，脚本生成另一个批处理文件，用于在安全模式下启动后执行修复操作

该批处理文件包括：
- 一些提示信息和警告。
- 删除受影响的文件。
- 恢复正常的启动配置。
- 重启系统。

如果未选择恢复选项 `'2'`，生成另外一个批处理文件 (`CSRemediationScript.bat`)，在未选择恢复选项 `'2'` 时，脚本生成一个不同的批处理文件，用于另一种修复方式

这个批处理文件主要包括：
- 检查BitLocker的状态。
- 根据返回码提示用户下一步操作。
- 允许用户输入替代的驱动器号，并重新尝试。
- 尝试解锁驱动器并删除受影响的文件。


总体来说，这段 PowerShell 脚本会根据用户选择的恢复选项，生成两个不同的批处理文件用于引导系统进入安全模式，并在安全模式中执行修复操作。 

这3段cmd命令大致如下,本身非常好获取，只需要执行一次代码，就可以在PE目录获得这些文件。
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

### 为PE添加包和驱动
`winpeshl.ini `是一种特定于 Windows 预安装环境（Windows PE）的配置文件，用于指定在 WinPE 启动时自动运行的应用程序。编写一个 `winpeshl.ini` 文件，需要了解一些基本的配置规则，如 `[LaunchApps]` 部分用于指定要启动的应用程序。这段脚本用于向 WinPE 镜像中添加必要的包和驱动程序，以便在 WinPE 启动时能够正常运行。具体来说，这段脚本会：

- 自动生成 winpeshl.ini 文件，以便 WinPE 启动时自动运行指定的恢复脚本。
- 添加必要的包（如 WMI 和 Secure Startup）以及对应的本地化包。
- 可选地根据用户输入添加额外的驱动程序到 WinPE 镜像中。

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


### 最后部分
这些 PowerShell 脚本用于创建和处理自定义 Windows 预安装环境（WinPE）镜像，并根据用户选择生成 ISO 文件或者将其写入 USB 驱动器

这里主要命令有两个：

- ` CopyPE amd64 "<WinPEStagingLocation>"`
- 这个命令是用来将WinPE的文件复制到一个指定的目录下，这个目录就是用来制作启动盘的目录。

- ` MakeWinPEMedia /ISO "<WinPEStagingLocation>" "<RecoveryImageLocation>"`
- 这个命令是用来创建一个WinPE的ISO文件，这个ISO文件可以用来制作一个启动盘，用来启动系统，然后进行修复操作。

- **`CopyPE`** 准备 WinPE 媒体环境，它并不会生成 ISO 文件，但它是生成 ISO 的前一步必要操作。
- **`MakeWinPEMedia /ISO`** 才是真正生成 ISO 文件的命令，它在第一步完成后被调用。


如果用户选择创建 USB 密钥，则进入相应的代码块，否则告知用户 ISO 文件的位置。

- 获取并验证 USB 驱动器的驱动器号。
- 验证 USB 驱动器是否存在且大小不超过 32GB。
- 格式化 USB 驱动器为 FAT32 文件系统。
- 挂载 ISO 文件，并将其内容复制到 USB 驱动器上。
- 卸载 ISO 文件，清理操作。

这里检测磁盘不超过32GB，可能是因为32GB是fat32文件系统的最大支持。在 Windows 系统中，使用内置工具（如磁盘管理器）格式化 FAT32 分区时，通常会限制在 32 GB 以下。

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
## 总结
汇总一下，该脚本的主要目的是通过自动化流程生成一个包含恢复工具的可启动USB设备或ISO文件，用于简化系统修复过程。

包括：

1. **下载和安装ADK**：脚本会检查并下载安装必要的ADK组件。
2. **提供选项和初始化环境**：管理员可以选择两种不同的恢复方案，脚本会根据选择进行环境配置。
3. **使用DISM挂载WinPE映像**：利用DISM工具挂载WinPE镜像以便后续修改。
4. **生成恢复批处理文件**：根据用户选择生成用于修复的批处理文件。
5. **为PE添加包和驱动**：向WinPE镜像中添加必要的包和驱动程序。
6. **创建ISO或USB密钥**：最终生成包含恢复工具的ISO文件或将其写入USB驱动器。

希望这篇文章能为大家在处理系统恢复问题时提供一些帮助，以及确保在测试和生产中引入微软的这个脚本，同时对修改脚本提供理论支持。
最后希望大家能够喜欢`PowerShell`
