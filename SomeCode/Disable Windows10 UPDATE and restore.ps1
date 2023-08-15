<#
.AUTHOR
MS pengliang 

.SYNOPSIS
管理 Windows 更新配置的 PowerShell 模块

.DESCRIPTION
包含用于禁用/启用 Windows 更新相关服务、计划任务、注册表及策略的函数。
可以方便地禁用或恢复 Windows 更新配置。

.PARAMETER SortBy
指定 Get-ConfigurationStatus 函数排序的属性名称,默认为"Name"。

.PARAMETER FilterConfigured
如果指定,Get-ConfigurationStatus 只返回配置状态为"未配置"的结果。

.EXAMPLE
PS> Restore-WindowsUpdateConfiguration

恢复 Windows 更新配置为默认启用状态。

.EXAMPLE

PS> Set-WindowsUpdateConfiguration

禁用 Windows 更新配置。

.EXAMPLE
PS> Get-ConfigurationStatus

获取 Windows 更新配置状态,按名称排序。

.EXAMPLE
PS> Get-ConfigurationStatus -SortBy "Value"

获取 Windows 更新配置状态,按配置状态值排序。

.EXAMPLE
PS> Get-ConfigurationStatus -FilterConfigured

只获取 Windows 更新未配置的项目状态。

.NOTES
需要管理员权限运行。

.LINK
https://docs.microsoft.com/zh-cn/powershell/

#>
function Set-WindowsUpdateConfiguration {
    [CmdletBinding()]
    param ()

    $result = @{}

    # 禁用Windows Update服务
    if ((Get-Service -Name wuauserv).Status -eq "Stopped" -and (Get-Service -Name wuauserv).StartType -eq "Disabled") {
        $result["服务-Windows Update"] = "已配置"
    } else {
        Stop-Service -Name wuauserv
        Set-Service -Name wuauserv -StartupType Disabled
        if ((Get-Service -Name wuauserv).Status -eq "Stopped" -and (Get-Service -Name wuauserv).StartType -eq "Disabled") {
            $result["服务-Windows Update"] = "已配置"
        } else {
            $result["服务-Windows Update"] = "未配置"
        }
    }

    # 禁用Windows Update Medic服务
    if ((Get-Service -Name WaaSMedicSvc).Status -eq "Stopped") {
        $result["服务-Windows Update Medic"] = "已配置"
    } else {
        Stop-Service -Name WaaSMedicSvc
        if ((Get-Service -Name WaaSMedicSvc).Status -eq "Stopped") {
            $result["服务-Windows Update Medic"] = "已配置"
        } else {
            $result["服务-Windows Update Medic"] = "未配置"
        }
    }

    # 禁用Windows Update ORCHESTRATOR服务
    if ((Get-Service -Name UsoSvc).Status -eq "Stopped" -and (Get-Service -Name UsoSvc).StartType -eq "Disabled") {
        $result["服务-Windows Update ORCHESTRATOR"] = "已配置"
    } else {
        Stop-Service -Name UsoSvc
        Set-Service -Name UsoSvc -StartupType Disabled
        if ((Get-Service -Name UsoSvc).Status -eq "Stopped" -and (Get-Service -Name UsoSvc).StartType -eq "Disabled") {
            $result["服务-Windows Update ORCHESTRATOR"] = "已配置"
        } else {
            $result["服务-Windows Update ORCHESTRATOR"] = "未配置"
        }
    }

    # 禁用更新任务
    $disableTaskResult = $null
    try {
        $disableTaskResult = Disable-ScheduledTask -TaskName "Microsoft\Windows\UpdateOrchestrator\*" -TaskPath "\Microsoft\Windows\UpdateOrchestrator" -ErrorAction Stop
        if ($disableTaskResult.Count -gt 0) {
            $result["计划任务-更新任务"] = "已配置"
        } else {
            $result["计划任务-更新任务"] = "未配置"
        }
    } catch {
        $result["计划任务-更新任务"] = "未配置"
    }

    # 修改Windows Update注册表
    $registryPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
    $registryName = "AUOptions"
    $registryValue = 1
    if (!(Test-Path -Path $registryPath)) {
        New-Item -Path $registryPath -Force | Out-Null
    }
    try {
        Set-ItemProperty -Path $registryPath -Name $registryName -Value $registryValue
        if ((Get-ItemProperty -Path $registryPath -Name $registryName).$registryName -eq $registryValue) {
            $result["注册表项-AUOptions"] = "已配置"
        } else {
            $result["注册表项-AUOptions"] = "未配置"
        }
    } catch {
        $result["注册表项-AUOptions"] = "未配置"
    }

    # 禁用组策略的Windows Update设置
    $policyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
    if (!(Test-Path -Path $policyPath)) {
        New-Item -Path $policyPath -Force | Out-Null
    }

    $policyNames = @("DisableWindowsUpdateAccess", "DisableWindowsUpdatePolicy")
    $setPolicySuccess = $true
    foreach ($policyName in $policyNames) {
        try {
            New-ItemProperty -Path $policyPath -Name $policyName -Value 1 -PropertyType "DWord" -Force | Out-Null
            if ((Get-ItemProperty -Path $policyPath -Name $policyName).$policyName -eq 1) {
                $result["策略-$policyName"] = "已配置"
            } else {
                $result["策略-$policyName"] = "未配置"
                $setPolicySuccess = $false
            }
        } catch {
            $result["策略-$policyName"] = "未配置"
            $setPolicySuccess = $false
        }
    }

    # 返回结果
    $result.GetEnumerator() | Select-Object -Property @{Name="名称";Expression={$_.Key}}, @{Name="配置状态";Expression={$_.Value}}
    Write-Output "更新任务配置状态： $($disableTaskResult -join ", ")"
    if ($setPolicySuccess) {
        Write-Output "策略项配置成功"
    } else {
        Write-Output "策略项配置失败"
    }
}
function Restore-WindowsUpdateConfiguration {
    [CmdletBinding()]
    param ()

    $result = @{}

    # 恢复Windows Update服务
    if ((Get-Service -Name wuauserv).Status -eq "Running" -and (Get-Service -Name wuauserv).StartType -eq "Manual") {
        $result["服务-Windows Update"] = "已配置"
    } else {
        Set-Service -Name wuauserv -StartupType Manual
        Start-Service -Name wuauserv
        if ((Get-Service -Name wuauserv).Status -eq "Running" -and (Get-Service -Name wuauserv).StartType -eq "Manual") {
            $result["服务-Windows Update"] = "已配置"
        } else {
            $result["服务-Windows Update"] = "未配置"
        }
    }

    # 恢复Windows Update Medic服务
    if ((Get-Service -Name WaaSMedicSvc).Status -eq "Running") {
        $result["服务-Windows Update Medic"] = "已配置"
    } else {
        Start-Service -Name WaaSMedicSvc
        if ((Get-Service -Name WaaSMedicSvc).Status -eq "Running") {
            $result["服务-Windows Update Medic"] = "已配置"
        } else {
            $result["服务-Windows Update Medic"] = "未配置"
        }
    }

    # 恢复Windows Update ORCHESTRATOR服务
    if ((Get-Service -Name UsoSvc).Status -eq "Running" -and (Get-Service -Name UsoSvc).StartType -eq "Manual") {
        $result["服务-Windows Update ORCHESTRATOR"] = "已配置"
    } else {
        Set-Service -Name UsoSvc -StartupType Manual

        Start-Service -Name UsoSvc
        if ((Get-Service -Name UsoSvc).Status -eq "Running" -and (Get-Service -Name UsoSvc).StartType -eq "Manual") {
            $result["服务-Windows Update ORCHESTRATOR"] = "已配置"
        } else {
            $result["服务-Windows Update ORCHESTRATOR"] = "未配置"
        }
    }

    # 恢复更新任务
    $enableTaskResult = $null
    try {
        $enableTaskResult = Enable-ScheduledTask -TaskName "Microsoft\Windows\UpdateOrchestrator\*" -TaskPath "\Microsoft\Windows\UpdateOrchestrator" -ErrorAction Stop
        if ($enableTaskResult.Count -gt 0) {
            $result["计划任务-更新任务"] = "已配置"
        } else {
            $result["计划任务-更新任务"] = "未配置"
        }
    } catch {
        $result["计划任务-更新任务"] = "未配置"
    }

    # 恢复Windows Update注册表
    $registryPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
    $registryName = "AUOptions"
    $registryValue = 0
    try {
        Set-ItemProperty -Path $registryPath -Name $registryName -Value $registryValue -ErrorAction Stop
        if ((Get-ItemProperty -Path $registryPath -Name $registryName).$registryName -eq $registryValue) {
            $result["注册表项-AUOptions"] = "已配置"
        } else {
            $result["注册表项-AUOptions"] = "未配置"
        }
    } catch {
        $result["注册表项-AUOptions"] = "未配置"
    }

    # 恢复组策略的Windows Update设置
    $policyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
    $policyNames = @("DisableWindowsUpdateAccess", "DisableWindowsUpdatePolicy")
    $restorePolicySuccess = $true
    foreach ($policyName in $policyNames) {
        try {
            Remove-ItemProperty -Path $policyPath -Name $policyName -ErrorAction Stop
            if (-not (Get-ItemProperty -Path $policyPath -Name $policyName -ErrorAction SilentlyContinue)) {
                $result["策略-$policyName"] = "已配置"
            } else {
                $result["策略-$policyName"] = "未配置"
                $restorePolicySuccess = $false
            }
        } catch {
            $result["策略-$policyName"] = "未配置"
            $restorePolicySuccess = $false
        }
    }

    # 返回结果
    $result.GetEnumerator() | Select-Object -Property @{Name="名称";Expression={$_.Key}}, @{Name="配置状态";Expression={$_.Value}}
    Write-Output "更新任务恢复状态： $($enableTaskResult -join ", ")"
    if ($restorePolicySuccess) {
        Write-Output "策略项恢复成功"
    } else {
        Write-Output "策略项恢复失败"
    }
}
 function Get-ConfigurationStatus {
    param (
        [string]$SortBy = "Name",
        [switch]$FilterConfigured
    )

    # 初始化结果对象
    $result = @{}

    # 检查Windows Update服务
    if ((Get-Service -Name wuauserv).Status -eq "Stopped" -and (Get-Service -Name wuauserv).StartType -eq "Disabled") {
        $result["服务-Windows Update"] = "已配置"
    } else {
        $result["服务-Windows Update"] = "未配置"
    }

    # 检查Windows Update Medic服务
    if ((Get-Service -Name WaaSMedicSvc).Status -eq "Stopped") {
        $result["服务-Windows Update Medic"] = "已配置"
    } else {
        $result["服务-Windows Update Medic"] = "未配置"
    }

    # 检查Windows Update ORCHESTRATOR服务
    if ((Get-Service -Name UsoSvc).Status -eq "Stopped" -and (Get-Service -Name UsoSvc).StartType -eq "Disabled") {
        $result["服务-Windows Update ORCHESTRATOR"] = "已配置"
    } else {
        $result["服务-Windows Update ORCHESTRATOR"] = "未配置"
    }

    # 检查计划任务
    $allScheduledTask='["Report policies","Schedule Scan","Schedule Scan Static Task","Start Oobe Expedite Work","StartOobeAppsScanAfterUpdate","StartOobeAppsScan_LicenseAccepted","USO_UxBroker","UUS Failover Task","Scheduled Start"]'|ConvertFrom-Json
    foreach ($task in $allScheduledTask) {
        if ((Get-ScheduledTask -TaskName $task).State -eq "Disabled") {
            $result["计划任务-$task"] = "已配置"
        } else {
            $result["计划任务-$task"] = "未配置"
        }
    }

    # 检查注册表项
    $registryPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
    $registryName = "AUOptions"
    if ((Get-ItemProperty -Path $registryPath -Name $registryName).$registryName -eq 1) {
        $result["注册表项-AUOptions"] = "已配置"
    } else {
        $result["注册表项-AUOptions"] = "未配置"
    }

    # 检查组策略项
    $policyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
    $policyNames = @("DisableWindowsUpdateAccess", "DisableWindowsUpdatePolicy")
    foreach ($policyName in $policyNames) {
        if ((Get-ItemProperty -Path $policyPath -Name $policyName).$policyName -eq 1) {
            $result["策略-$policyName"] = "已配置"
        } else {
            $result["策略-$policyName"] = "未配置"
        }
    }

    # 对结果进行排序
    $sortedResults = $result.GetEnumerator() | Sort-Object -Property $SortBy

    # 如果选择过滤已配置/未配置项，则进行筛选
    if ($FilterConfigured) {
        if ($SortBy -eq "Name") {
            $filteredResults = $sortedResults | Where-Object { $_.Value -eq "未配置" }
        } else {
            $filteredResults = $sortedResults | Where-Object { $_.Key -eq "未配置" }
        }
        $filteredResults
    } else {
        $sortedResults
    }
}


<#
# 恢复更新示例用法
Restore-WindowsUpdateConfiguration
# 禁用更新示例用法
Set-WindowsUpdateConfiguration
# 获取所有结果并按名称排序
Get-ConfigurationStatus -SortBy "Name"
# 获取所有结果并按值排序
Get-ConfigurationStatus -SortBy "Value"
# 获取只包含未配置项的结果，并按名称排序
Get-ConfigurationStatus -SortBy "Name" -FilterConfigured

#>
