

#从所有虚拟机获取挂载的磁盘，生成磁盘的LUN排序，以及磁盘的ID
function GetFullVMSdisk ($outputfilename) {
    <#
.SYNOPSIS
   此函数用于获取 Azure 订阅中所有虚拟机的 OS 和 Data 磁盘 ID 信息，并将结果以 CSV 格式写入指定文件。
.DESCRIPTION
   GetFullVMSdisk 函数通过调用 Get-AzVM 命令来获取 Azure 订阅中所有虚拟机的 OS 和 Data 磁盘 ID 信息，并将结果以 CSV 格式写入指定文件。其中，磁盘信息包括虚拟机名称、磁盘标签(`OsVhd` 表示操作系统磁盘，`DataVhdX` 表示数据磁盘 X)、以及磁盘的唯一标识符。输出格式为 "rolename,disklabel,id" + 虚拟机名称 + "," + 磁盘标签 + "," + 磁盘 ID。
.PARAMETER outputfilename
    字符串类型，必需参数。指定输出结果的文件名和路径。
.EXAMPLE
   GetFullVMSdisk -outputfilename "C:\Temp\DiskID.csv"
   描述：此例将获取所有 Azure 虚拟机的 OS 和 Data 磁盘 ID 信息，并将结果写入到 "C:\Temp\DiskID.csv" 中。
.INPUTS
   存储文件名.
.OUTPUTS
   该函数将返回以下列格式以 CSV 文件形式存储的所有 Azure 虚拟机的 OS 和 Data 磁盘 ID 信息：
    - rolename 列：虚拟机名称；
    - disklabel 列：磁盘标签(`OsVhd` 表示操作系统磁盘，`DataVhdX` 表示数据磁盘 X)；
    - id 列：磁盘的唯一标识符。
   同时，该函数会在输出文件的第一行添加列标题 "rolename,disklabel,id"，并在执行完毕后提示 “输出完成，请检查 <outputfilename>” 的消息。

#>
    $azVMS = Get-AzVM
    "获取完成所有VM，请等待"
    $azVMSwithID = $azVMS | ForEach-Object { $tempvm = $_
        $tempvm2 = $tempvm | Select-Object name, ResourceGroupName, @{l = "OSdiskID"; e = { $_.StorageProfile.OsDisk.ManagedDisk.Id } }   
        $tempvm2.name + "," + "OsVhd" + "," + $tempvm2.OSdiskID 
        if ($tempvm.StorageProfile.DataDisks) {
            $tempvm.StorageProfile.DataDisks | ForEach-Object { $tempvm.name + "," + "DataVhd" + $_.lun + "," + $_.manageddisk.Id #+ "," +
            }
        }
    } 
    "rolename,disklabel,id" | Out-File $outputfilename -Encoding utf8 -Force
    $azVMSwithID | Out-File $outputfilename -Encoding utf8 -Force -Append  
    "输出完成，请检查" + $outputfilename
}





#获取所有磁盘的ID/SKU/磁盘本身的水位限制
function GetFulldisksInfo {
    <#
.SYNOPSIS 
获取 Azure 环境中的所有磁盘信息并输出到 CSV 文件。

.DESCRIPTION 
GetFulldisksInfo 函数可以用于获取 Azure 环境中的所有磁盘信息并输出到 CSV 文件。

.PARAMETER outputfilename
指定输出文件的完整路径和名称，必须是字符串类型。

.EXAMPLE 
GetFulldisksInfo -outputfilename "C:\Temp\disks.csv"
此示例将所有磁盘信息写入到 C:\Temp\disks.csv 文件中。

.NOTES 
运行之前确保已安装且配置适当的 Azure PowerShell 模块，以便可以运行 Get-AzDisk 命令获取 Azure 环境中的磁盘信息。
#>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$outputfilename
    )
    
    Get-AzDisk | Select-Object id, DiskSizeGB, DiskIOPSReadWrite, DiskMBpsReadWrite, Tier, @{l = "SKUname"; e = { $_.sku.name } }`
    | Export-Csv  $outputfilename  -Encoding utf8 -Force  

    Write-Host "输出完成，请检查 $outputfilename"
}

#GetFullVMSdisk -outputfilename  VMDisksID.csv
#GetFulldisksInfo -outputfilename VMDisksWithinfo.csv





 