<# 

    Create Deployment server with.
    4 vCpu
    8Gb Ram
    50Gb OS Drive
    100GB Data Drive

    Auto Download Server 2025 Eval.
    https://software-static.download.prss.microsoft.com/dbazure/888969d5-f34g-4e03-ac9d-1f9786c66749/26100.1742.240906-0331.ge_release_svc_refresh_SERVER_EVAL_x64FRE_en-us.iso

    Auto Download Server 2022 Eval.
    https://software-static.download.prss.microsoft.com/sg/download/888969d5-f34g-4e03-ac9d-1f9786c66749/SERVER_EVAL_x64FRE_en-us.iso

    Auto Download VirtIO Drivers.
    https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/latest-virtio/virtio-win.iso
    
    Start the VM and initiate Windows Installation.

#>


# Name of the "Master" VM
# ------------------------------------------------------------
$VMName               = "CoreDeployment"
$DefaultAdminPassword = "P@ssw0rd2025$"
$ServerVersionsISO    = @("2019","2022","2025")
$SelectedOS = $ServerVersionsISO | Out-GridView -Title "Select the Deployment Server OS Version" -OutputMode Single


# Path to PVE scripts and Functions.
# ------------------------------------------------------------
$TempPath = "$($ENV:Temp)\PVE"


<# Get all required json configurations #>


# Load Windows Forms
# ------------------------------------------------------------
Add-Type -AssemblyName System.Windows.Forms
$FileDialog = New-Object System.Windows.Forms.OpenFileDialog
$FileDialog.Filter = "JSON files (*.json)|*.json"


# Get License Key from JSON
# ------------------------------------------------------------
$FileDialog.Title  = "Select Product keys file"
if ($FileDialog.ShowDialog() -eq "OK") {
    $ProductKeys = Get-Content -Path $FileDialog.FileName | ConvertFrom-Json
    $ProductKey  = ($ProductKeys | Where {$_.Product -like "Windows Server *$SelectedOS*Standard"}).Key
}
else {
    Write-Warning "No file selected"
    Write-Host "Download and execute `"InfraAsCode/Secrets/Scripts/Create-GitHubConfig.ps1`" and rerun this script"
}


# Define the GIT connection information, If the Repo is private.
# ------------------------------------------------------------
$FileDialog.Title  = "Select GIThub secrets file"
if ($FileDialog.ShowDialog() -eq "OK") {
    $GitConnection = Get-Content -Path $FileDialog.FileName | ConvertFrom-Json
}
else {
    Write-Warning "No file selected"
    Write-Host "Download and execute `"InfraAsCode/Secrets/Scripts/Create-GitHubConfig.ps1`" and rerun this script"
}


# Open PVE Secrets file
# ------------------------------------------------------------
$FileDialog.Title  = "Select Proxmox Secrets file"
if ($FileDialog.ShowDialog() -eq "OK") {
    $PVESecret  = Get-Content $FileDialog.FileName | Convertfrom-Json
}
else {
    Write-Warning "No file selected"
    Write-Host "Download and execute `"InfraAsCode/Secrets/Scripts/Create-ProxmoxConfig.ps1`" and rerun this script"
}


<# Main Script #>


# Create Required folders
# ------------------------------------------------------------
If (-Not (Test-Path "$TempPath")) {
    New-Item -Path "$TempPath" -ItemType Directory | Out-Null
}
If (-Not (Test-Path "$TempPath\Functions")) {
    New-Item -Path "$TempPath\Functions" -ItemType Directory | Out-Null
}


# Get required PVE modules
# ------------------------------------------------------------
$RequiredScripts = @()
$RequiredScripts += [pscustomobject]@{ LocalPath = "\Functions"; RemotePath = "InfraAsCode/contents/Platforms/PVE/Functions/Get-PVELocation.ps1" }
$RequiredScripts += [pscustomobject]@{ LocalPath = "\Functions"; RemotePath = "InfraAsCode/contents/Platforms/PVE/Functions/Get-PVENextID.ps1"   }
$RequiredScripts += [pscustomobject]@{ LocalPath = "\Functions"; RemotePath = "InfraAsCode/contents/Modules/New-ISOFile.ps1"                     }
$RequiredScripts += [pscustomobject]@{ LocalPath = "\Functions"; RemotePath = "InfraAsCode/contents/Modules/New-Unattend.ps1"                    }
$RequiredScripts += [pscustomobject]@{ LocalPath = "\Functions"; RemotePath = "InfraAsCode/contents/Platforms/PVE/Functions/PVE-Connect.ps1"     }
$RequiredScripts += [pscustomobject]@{ LocalPath = "\Functions"; RemotePath = "InfraAsCode/contents/Platforms/PVE/Functions/Start-PVEWait.ps1"   }
$RequiredScripts += [pscustomobject]@{ LocalPath = "\Functions"; RemotePath = "InfraAsCode/contents/Platforms/PVE/Functions/Upload-PVEISO.ps1"   }
$RequiredScripts += [pscustomobject]@{ LocalPath = ""; RemotePath = "InfraTools/contents/DeploymentService/Prep-DeploymentServer.ps1"            }
$RequiredScripts += [pscustomobject]@{ LocalPath = ""; RemotePath = "InfraTools/contents/DeploymentService/DeploymentServerFiles.json"           }


$RequiredScripts | Foreach {
    $LocalFile = Split-Path -Path $_.RemotePath -Leaf
    $FilePath  = Join-Path -Path $TempPath -ChildPath "$($_.LocalPath)\$LocalFile"
    
    if (-Not (Test-Path -Path $FilePath)) {

        if ( ($GitConnection.Token) -and ($GitConnection.Token -Notlike "*<Token>*") ) {
            $Response = Invoke-RestMethod -Uri "$($GitConnection.Url)/$($_.RemotePath)" -Headers @{ Authorization = "token $($GitConnection.Token)" }
        } else {
            $Response = Invoke-RestMethod -Uri "$($GitConnection.Url)/$($_.RemotePath)"
        }
    
        $FileBytes = [System.Convert]::FromBase64String($Response.content)
        [System.IO.File]::WriteAllBytes($FilePath, $FileBytes)
    }
}


# Required to import unsigned modules
# ------------------------------------------------------------
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force -Confirm:$false


# Import PVE modules
# ------------------------------------------------------------
Get-ChildItem -Path "$TempPath\Functions" | ForEach-Object { Import-Module -Name $_.FullName -Force }
if ( (-Not (Get-Command PVE-Connect)) -or (-NOT (Get-Command New-ISOFile)) ) {
    Throw "Unable to load modules"
    break
}


# Connect to PVE Cluster
# -------------------.-----------------------------------------
if ($PVESecret.count -gt 1) {
    $PVESecret = $PVESecret | Out-GridView -Title "Select `"Master`" NODE" -OutputMode Single
}
$PVEConnect = PVE-Connect -Authkey "$($PVESecret.User)!$($PVESecret.TokenID)=$($PVESecret.Token)" -Hostaddr $($PVESecret.Host)


# Get information required to create the template (VM)
# ------------------------------------------------------------
$PVELocation = Get-PVELocation -ProxmoxAPI $PVEConnect.PVEAPI -Headers $PVEConnect.Headers -IncludeNode $PVESecret.HostName
$ISOStorage  = ((Invoke-RestMethod -Uri "$($PVEConnect.PVEAPI)/nodes/$($PVELocation.name)/storage" -Headers $($PVEConnect.Headers)).data | Where {$_.content -like "*iso*" -and $_.type -eq "dir"}).storage


# Download Windows Server EVAL Isos
# ------------------------------------------------------------
$DownloadResults = @()
$ServerVersionsISO | Foreach {

    $response = Invoke-WebRequest -Uri "https://www.microsoft.com/en-us/evalcenter/download-windows-server-$($_)" -UseBasicParsing
    $DownloadUrl = ($response.Links | Where { $_.'aria-label' -like "*ISO*en-US*" }).href

    $DownloadBody = "content=iso"
    $DownloadBody += "&node=$($PVELocation.name)"
    $DownloadBody += "&url=$([uri]::EscapeDataString($DownloadUrl))"
    $DownloadBody += "&filename=$([uri]::EscapeDataString("Server$($_).iso"))"

    $DownloadResults += [pscustomobject]@{
        Version = $($_);
        Result = $(Invoke-RestMethod -Method POST -Uri "$($PVEConnect.PVEAPI)/nodes/$($PVELocation.name)/storage/$ISOStorage/download-url" -Headers $($PVEConnect.Headers) -Body $DownloadBody).data
    }
}


# Download VirtIO Windows Drivers.
# ------------------------------------------------------------
$DownloadBody  = "content=iso"
$DownloadBody += "&node=$($PVELocation.name)"
$DownloadBody += "&url=$([uri]::EscapeDataString("https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/latest-virtio/virtio-win.iso"))"
$DownloadBody += "&filename=$([uri]::EscapeDataString("virtio-win.iso"))"

$DriverResult = Invoke-RestMethod -Method POST -Uri "$($PVEConnect.PVEAPI)/nodes/$($PVELocation.name)/storage/$ISOStorage/download-url" -Headers $($PVEConnect.Headers) -Body $DownloadBody
$DownloadResults += [pscustomobject]@{
    Version = "";
    Result = $DriverResult.data
}


# Next avalible High VMID
# ------------------------------------------------------------
$VMID = Get-PVENextID -ProxmoxAPI $($PVEConnect.PVEAPI) -Headers $($PVEConnect.Headers)


# Create Temp folder, to be converted to ISO.
# ------------------------------------------------------------
If (-NOT(Test-Path -Path "$($env:TEMP)\$VMID")) {
    New-Item -Path "$($env:TEMP)\$VMID" -ItemType Directory | Out-Null
}



<#
    
    Copy Prep scripts to AutoUnattended ISO folder.

#>


# Create Scripts folder on "Deployment media"
# ------------------------------------------------------------
if (-Not(Test-Path -Path "$($env:TEMP)\$VMID\Scripts")) {
    New-Item -Path "$($env:TEMP)\$VMID\Scripts" -ItemType Directory | Out-Null
}


# Copy required files to prepare the Deployment Server
# ------------------------------------------------------------
#Move-Item -Path "$TempPath\Prep-DeploymentServer.ps1" -Destination "$($env:TEMP)\$VMID\Scripts"
#Move-Item -Path "$TempPath\DeploymentServerFiles.json" -Destination "$($env:TEMP)\$VMID\Scripts"
Copy-Item -Path "$TempPath\Prep-DeploymentServer.ps1" -Destination "$($env:TEMP)\$VMID\Scripts"
Copy-Item -Path "$TempPath\DeploymentServerFiles.json" -Destination "$($env:TEMP)\$VMID\Scripts"
<#
Start "$($env:TEMP)\$VMID\Scripts"
#>


# Save / Copy the PVE and GIT connection infomation.
# ------------------------------------------------------------
$GitConnection | ConvertTo-Json | Out-File -FilePath "$($env:TEMP)\$VMID\Scripts\GitHub-Connection.json" -Encoding utf8
$PVESecret     | ConvertTo-Json | Out-File -FilePath "$($env:TEMP)\$VMID\Scripts\Proxmox-Connection.json" -Encoding utf8


# Create AutoUnattended.iso
# ------------------------------------------------------------
<#

    Encode the FirstLogonCommands !

    [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes("GCI (((Get-Volume -FileSystemLabel `"virtio-win*`").DriveLetter) + `":\`") -Recurse -Include *.inf | ? { `$_.FullName -match `"2K25`" -and `$_.FullName -match `"AMD`" } | % { pnputil /add-Driver `$_.FullName /install }"))
    [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes("mkdir -Path `"`$(`$ENV:SystemDrive)\Scripts`"; Get-Volume | Where {`$_.DriveType -eq `"CD-Rom`"} | % { if (Test-Path -Path `"`$(`$_.DriveLetter):\Scripts`") { GCI -Path `"`$(`$_.DriveLetter):\Scripts`" | % { Copy -Path `$(`$_.FullName) -Destination `"`$(`$ENV:SystemDrive)\Scripts`" -Force }}}; GCI -Path `"`$(`$ENV:SystemDrive)\Scripts`" -Recurse | % {`$_.IsReadOnly = `$false}"))
    [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes("& `"C:\Scripts\Prep-DeploymentServer.ps1`""))

#>
New-Unattend -ComputerName $VMName -AdminUsername "Administrator" -AdminPassword $DefaultAdminPassword `
    -ProductKey $ProductKey `
    -FirstLogonCommands @(
        [PSCustomObject]@{ Name = "Add Drivers";  Command = "PowerShell -NoProfile -ExecutionPolicy Bypass -EncodedCommand RwBDAEkAIAAoACgAKABHAGUAdAAtAFYAbwBsAHUAbQBlACAALQBGAGkAbABlAFMAeQBzAHQAZQBtAEwAYQBiAGUAbAAgACIAdgBpAHIAdABpAG8ALQB3AGkAbgAqACIAKQAuAEQAcgBpAHYAZQBMAGUAdAB0AGUAcgApACAAKwAgACIAOgBcACIAKQAgAC0AUgBlAGMAdQByAHMAZQAgAC0ASQBuAGMAbAB1AGQAZQAgACoALgBpAG4AZgAgAHwAIAA/ACAAewAgACQAXwAuAEYAdQBsAGwATgBhAG0AZQAgAC0AbQBhAHQAYwBoACAAIgAyAEsAMgA1ACIAIAAtAGEAbgBkACAAJABfAC4ARgB1AGwAbABOAGEAbQBlACAALQBtAGEAdABjAGgAIAAiAEEATQBEACIAIAB9ACAAfAAgACUAIAB7ACAAcABuAHAAdQB0AGkAbAAgAC8AYQBkAGQALQBEAHIAaQB2AGUAcgAgACQAXwAuAEYAdQBsAGwATgBhAG0AZQAgAC8AaQBuAHMAdABhAGwAbAAgAH0A" }
        [PSCustomObject]@{ Name = "Copy Scripts"; Command = "PowerShell -NoProfile -ExecutionPolicy Bypass -EncodedCommand bQBrAGQAaQByACAALQBQAGEAdABoACAAIgAkACgAJABFAE4AVgA6AFMAeQBzAHQAZQBtAEQAcgBpAHYAZQApAFwAUwBjAHIAaQBwAHQAcwAiADsAIABHAGUAdAAtAFYAbwBsAHUAbQBlACAAfAAgAFcAaABlAHIAZQAgAHsAJABfAC4ARAByAGkAdgBlAFQAeQBwAGUAIAAtAGUAcQAgACIAQwBEAC0AUgBvAG0AIgB9ACAAfAAgACUAIAB7ACAAaQBmACAAKABUAGUAcwB0AC0AUABhAHQAaAAgAC0AUABhAHQAaAAgACIAJAAoACQAXwAuAEQAcgBpAHYAZQBMAGUAdAB0AGUAcgApADoAXABTAGMAcgBpAHAAdABzACIAKQAgAHsAIABHAEMASQAgAC0AUABhAHQAaAAgACIAJAAoACQAXwAuAEQAcgBpAHYAZQBMAGUAdAB0AGUAcgApADoAXABTAGMAcgBpAHAAdABzACIAIAB8ACAAJQAgAHsAIABDAG8AcAB5ACAALQBQAGEAdABoACAAJAAoACQAXwAuAEYAdQBsAGwATgBhAG0AZQApACAALQBEAGUAcwB0AGkAbgBhAHQAaQBvAG4AIAAiACQAKAAkAEUATgBWADoAUwB5AHMAdABlAG0ARAByAGkAdgBlACkAXABTAGMAcgBpAHAAdABzACIAIAAtAEYAbwByAGMAZQAgAH0AfQB9AA==" }
        [PSCustomObject]@{ Name = "Run Scripts";  Command = "PowerShell -NoProfile -ExecutionPolicy Bypass -EncodedCommand JgAgACIAQwA6AFwAUwBjAHIAaQBwAHQAcwBcAFAAcgBlAHAALQBEAGUAcABsAG8AeQBtAGUAbgB0AFMAZQByAHYAZQByAC4AcABzADEAIgA=" }
    ) | `
    Out-File -FilePath "$($env:TEMP)\$VMID\AutoUnattend.xml" -Encoding utf8 -Force
    <#
    notepad "$($env:TEMP)\$VMID\AutoUnattend.xml"
    #>


#region XML Unattend modifications

# Load XML data
# ------------------------------------------------------------
$XMLData = [XML](Get-Content -Path "$($env:TEMP)\$VMID\AutoUnattend.xml")

# Define Namespaces
# ------------------------------------------------------------
$NS  = $XMLData.DocumentElement.NamespaceURI
$WCMNS = "http://schemas.microsoft.com/WMIConfig/2002/State"


# Define Driver Paths.
# ------------------------------------------------------------
$DriverPaths = @(
    "D:\vioscsi\2k25\amd64",
    "E:\vioscsi\2k25\amd64",
    "F:\vioscsi\2k25\amd64",
    "G:\vioscsi\2k25\amd64"
)


# Helper Functions.
# ------------------------------------------------------------
function New-XmlEl {
    param($Name, $Value = $null)
    $EL = $XMLData.CreateElement($Name, $NS)
    if ($Value) { [void]($EL.InnerText = $Value) }
    return $EL
}

function New-XmlElWcm {
    param($Name)
    $EL = $XMLData.CreateElement($Name, $NS)
    [void]($EL.SetAttribute("action", $WCMNS, "add"))
    return $EL
}

function New-XmlElWcm2 {
    param($Name, $KeyValue)
    $EL = $XMLData.CreateElement($Name, $NS)
    [void]($EL.SetAttribute("action", $WCMNS, "add"))
    [void]($EL.SetAttribute("keyValue", $WCMNS, $KeyValue))
    return $EL
}

function New-DriverPaths {
    param($Paths)
    $NewDriverPaths = New-XmlEl "DriverPaths"
    $i = 1
    foreach ($Path in $Paths) {
        $Pac = New-XmlElWcm2 "PathAndCredentials" "$i"
        $Pac.AppendChild((New-XmlEl "Path" $Path)) | Out-Null
        $NewDriverPaths.AppendChild($Pac) | Out-Null
        $i++
    }
    return $NewDriverPaths
}


# Get the Microsoft-Windows-Setup component in windowsPE pass
# - DiskConfiguration and ImageInstall
# ------------------------------------------------------------
$Component = ($XMLData.unattend.settings | Where { $_.pass -eq "windowsPE" }).component | Where { $_.name -eq "Microsoft-Windows-Setup" }


# DiskConfiguration
# ------------------------------------------------------------
$DiskConfig = New-XmlEl "DiskConfiguration"

$Disk = New-XmlElWcm "Disk"
$Disk.AppendChild((New-XmlEl "DiskID" "0")) | Out-Null
$Disk.AppendChild((New-XmlEl "WillWipeDisk" "true")) | Out-Null

# CreatePartitions
# ------------------------------------------------------------
$CreateParts = New-XmlEl "CreatePartitions"

$CP1 = New-XmlElWcm "CreatePartition"
$CP1.AppendChild((New-XmlEl "Order" "1")) | Out-Null
$CP1.AppendChild((New-XmlEl "Type" "EFI")) | Out-Null
$CP1.AppendChild((New-XmlEl "Size" "100")) | Out-Null

$CP2 = New-XmlElWcm "CreatePartition"
$CP2.AppendChild((New-XmlEl "Order" "2")) | Out-Null
$CP2.AppendChild((New-XmlEl "Type" "MSR")) | Out-Null
$CP2.AppendChild((New-XmlEl "Size" "128")) | Out-Null

$CP3 = New-XmlElWcm "CreatePartition"
$CP3.AppendChild((New-XmlEl "Order" "3")) | Out-Null
$CP3.AppendChild((New-XmlEl "Type" "Primary")) | Out-Null
$CP3.AppendChild((New-XmlEl "Extend" "true")) | Out-Null

$CreateParts.AppendChild($CP1) | Out-Null
$CreateParts.AppendChild($CP2) | Out-Null
$CreateParts.AppendChild($CP3) | Out-Null

# ModifyPartitions
# ------------------------------------------------------------
$ModifyParts = New-XmlEl "ModifyPartitions"

$MP1 = New-XmlElWcm "ModifyPartition"
$MP1.AppendChild((New-XmlEl "Order" "1")) | Out-Null
$MP1.AppendChild((New-XmlEl "PartitionID" "1")) | Out-Null
$MP1.AppendChild((New-XmlEl "Format" "FAT32")) | Out-Null
$MP1.AppendChild((New-XmlEl "Label" "System")) | Out-Null

$MP2 = New-XmlElWcm "ModifyPartition"
$MP2.AppendChild((New-XmlEl "Order" "2")) | Out-Null
$MP2.AppendChild((New-XmlEl "PartitionID" "2")) | Out-Null

$MP3 = New-XmlElWcm "ModifyPartition"
$MP3.AppendChild((New-XmlEl "Order" "3")) | Out-Null
$MP3.AppendChild((New-XmlEl "PartitionID" "3")) | Out-Null
$MP3.AppendChild((New-XmlEl "Format" "NTFS")) | Out-Null
$MP3.AppendChild((New-XmlEl "Label" "Windows")) | Out-Null
$MP3.AppendChild((New-XmlEl "Letter" "C")) | Out-Null

$ModifyParts.AppendChild($mp1) | Out-Null
$ModifyParts.AppendChild($mp2) | Out-Null
$ModifyParts.AppendChild($mp3) | Out-Null

$Disk.AppendChild($CreateParts) | Out-Null
$Disk.AppendChild($ModifyParts) | Out-Null

$DiskConfig.AppendChild($Disk) | Out-Null

# Append DiskConfiguration to the component
# ------------------------------------------------------------
$Component.AppendChild($diskConfig) | Out-Null


# ImageInstall
# ------------------------------------------------------------
$ImageInstall = New-XmlEl "ImageInstall"

$OSImage = New-XmlEl "OSImage"

$InstallFrom = New-XmlEl "InstallFrom"

$MetaData = New-XmlElWcm "MetaData"
$MetaData.AppendChild((New-XmlEl "Key" "/IMAGE/INDEX")) | Out-Null
$MetaData.AppendChild((New-XmlEl "Value" "2")) | Out-Null

$InstallFrom.AppendChild($MetaData) | Out-Null

$InstallTo = New-XmlEl "InstallTo"
$InstallTo.AppendChild((New-XmlEl "DiskID" "0")) | Out-Null
$InstallTo.AppendChild((New-XmlEl "PartitionID" "3")) | Out-Null

$OSImage.AppendChild($InstallFrom) | Out-Null
$OSImage.AppendChild($InstallTo) | Out-Null

$ImageInstall.AppendChild($OSImage) | Out-Null

# Append after DiskConfiguration
# ------------------------------------------------------------
$Component.AppendChild($ImageInstall) | Out-Null


# WinPE Driver component
# - added to existing windowsPE settings
# ------------------------------------------------------------
$WinPESettings = $XMLData.unattend.settings | Where { $_.pass -eq "windowsPE" }

$WinPEDriverComp = $XMLData.CreateElement("component", $NS)
$WinPEDriverComp.SetAttribute("name", "Microsoft-Windows-PnpCustomizationsWinPE")
$WinPEDriverComp.SetAttribute("processorArchitecture", "amd64")
$WinPEDriverComp.SetAttribute("publicKeyToken", "31bf3856ad364e35")
$WinPEDriverComp.SetAttribute("language", "neutral")
$WinPEDriverComp.SetAttribute("versionScope", "nonSxS")
$WinPEDriverComp.SetAttribute("xmlns:xsi", "http://www.w3.org/2001/XMLSchema-instance")
$WinPEDriverComp.AppendChild((New-DriverPaths $DriverPaths)) | Out-Null

$WinPESettings.AppendChild($WinPEDriverComp) | Out-Null


# offlineServicing settings node
# ------------------------------------------------------------
$OfflineSettings = $XMLData.CreateElement("settings", $NS)
$OfflineSettings.SetAttribute("pass", "offlineServicing")

$OfflineComp = $XMLData.CreateElement("component", $NS)
$OfflineComp.SetAttribute("name", "Microsoft-Windows-PnpCustomizationsNonWinPE")
$OfflineComp.SetAttribute("processorArchitecture", "amd64")
$OfflineComp.SetAttribute("publicKeyToken", "31bf3856ad364e35")
$OfflineComp.SetAttribute("language", "neutral")
$OfflineComp.SetAttribute("versionScope", "nonSxS")
$OfflineComp.SetAttribute("xmlns:xsi", "http://www.w3.org/2001/XMLSchema-instance")
$OfflineComp.AppendChild((New-DriverPaths $DriverPaths)) | Out-Null

$OfflineSettings.AppendChild($OfflineComp) | Out-Null
$XMLData.unattend.AppendChild($OfflineSettings) | Out-Null


# Save the upadted XML
# ------------------------------------------------------------
$XMLData.Save("$($env:TEMP)\$VMID\AutoUnattend.xml")

<# --- XML Unattend modifications --- #>
#endregion


# Create Unattended ISO
# ------------------------------------------------------------
$null = New-ISOFile -source "$($env:TEMP)\$VMID" -destinationIso "$($env:TEMP)\$VMID.iso" -force


# Upload ISO to PVE Node.
# ------------------------------------------------------------
$null = Upload-PVEISO -ProxmoxAPI $($PVEConnect.PVEAPI) -Headers $($PVEConnect.Headers) -Node $($PVELocation.Name) -Storage $ISOStorage -IsoPath "$($env:TEMP)\$VMID.iso"


# Cleanup Temp Deployment media folder and ISO file
# ------------------------------------------------------------
<#
Start "$($env:TEMP)\$VMID"
#>
Remove-Item -Path "$($env:TEMP)\$VMID" -Recurse -Force -Confirm:$false
Remove-Item -Path "$($env:TEMP)\$VMID.iso" -Force -Confirm:$false


# Wait all downloads.
# ------------------------------------------------------------
$DownloadResults | Foreach {
    Start-PVEWait -ProxmoxAPI $($PVEConnect.PVEAPI) -Headers $PVEConnect.Headers -node $($PVELocation.Name) -taskid $_.Result
}


# Get ISO Content and Add the files to the Deployment VM
# ---
$ISOFiles      = ((Invoke-RestMethod -Uri "$($PVEConnect.PVEAPI)/nodes/$($PVELocation.name)/storage/$ISOStorage/content" -Headers $($PVEConnect.Headers)).data).volid
$DriverMedia   = $ISOFiles | Where {$_ -like "*$(($DriverResult.data -split(":"))[6])"}
$UnattendMedia = $ISOFiles | Where {$_ -like "*$VMID*.iso"}
$InstallMedia = $ISOFiles | Where {$_ -like "*$SelectedOS*"}
if ($InstallMedia.count -gt 1) {
    $InstallMedia = $InstallMedia | Out-GridView -Title "Multiple ISO files exist, please select one" -OutputMode Single
}
<#
$DriverMedia   = $ISOFiles | Where {$_ -like "*virtio-win*"}
$InstallMedia  = $ISOFiles | Where {$_ -like "*server_2025*"}
#>


# Default Deployent Sever Configuration
# ------------------------------------------------------------
$CreateVM = "node=$($PVELocation.Name)"
$CreateVM += "&vmid=$VMID"
$CreateVM += "&name=$VMName"
$CreateVM += "&bios=ovmf"
$CreateVM += "&cpu=x86-64-v2-AES"
$CreateVM += "&ostype=win11"
$CreateVM += "&machine=pc-q35-9.0"
$CreateVM += "&tpmstate0=$([uri]::EscapeDataString("$($PVELocation.storage):1,size=4M,version=v2.0"))"
$CreateVM += "&efidisk0=$([uri]::EscapeDataString("$($PVELocation.storage):1,efitype=4m,format=raw,pre-enrolled-keys=1"))"
$CreateVM += "&net0=$([uri]::EscapeDataString("virtio,bridge=$($PVELocation.Interface),firewall=1"))"
$CreateVM += "&boot=$([uri]::EscapeDataString("order=scsi0;ide2"))"
$CreateVM += "&scsihw=virtio-scsi-single"
$CreateVM += "&memory=8192"
$CreateVM += "&balloon=2048"
$CreateVM += "&cores=4"
$CreateVM += "&scsi0=$([uri]::EscapeDataString("$($PVELocation.storage):100,ssd=on,format=raw"))"
$CreateVM += "&ide0=$([uri]::EscapeDataString("$InstallMedia,media=cdrom"))"
$CreateVM += "&ide1=$([uri]::EscapeDataString("$DriverMedia,media=cdrom"))"
$CreateVM += "&ide2=$([uri]::EscapeDataString("$UnattendMedia,media=cdrom"))"


# Create the Template VM
# ------------------------------------------------------------
$VMCreate = Invoke-RestMethod -Uri "$($PVEConnect.PVEAPI)/nodes/$($PVELocation.Name)/qemu/" -Body $CreateVM -Method POST -Headers $($PVEConnect.Headers)
Start-PVEWait -ProxmoxAPI $($PVEConnect.PVEAPI) -Headers $PVEConnect.Headers -node $($PVELocation.Name) -taskid $VMCreate.data


# Start new server
# ------------------------------------------------------------
$null = Invoke-RestMethod -Uri "$($PVEConnect.PVEAPI)/nodes/$($PVELocation.name)/qemu/$VMID/status/start" -Headers $($PVEConnect.Headers) -Method POST


# Press ANY key to boot from Windows Installation media.
# ------------------------------------------------------------
$SendKey = "node=$($PVELocation.Name)"
$SendKey += "&vmid=$VMID"
$SendKey += "&command=sendkey a"

for ($i=0; $i -lt 5; $i++) {
    Invoke-RestMethod -Method POST -Uri "$($PVEConnect.PVEAPI)/nodes/$($PVELocation.name)/qemu/$VMID/monitor" -Headers $($PVEConnect.Headers) -Body $SendKey
    Start-Sleep -Seconds 2
}
