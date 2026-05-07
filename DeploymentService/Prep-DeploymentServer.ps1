<# 

    Find and format the Data Drive.
    Create folder structure.
    Download scripts from Github.
    Install Windows ADK - WinPE

#>


# Path to PVE scripts and Functions.
# ------------------------------------------------------------
if ($PSScriptRoot -and $PSScriptRoot -ne "") {
    $RootPath = $PSScriptRoot
} else {
    $RootPath  = "C:\Scripts"
}


<# Get all required json files #>


# Load Windows Forms
# ------------------------------------------------------------
Add-Type -AssemblyName System.Windows.Forms
$FileDialog = New-Object System.Windows.Forms.OpenFileDialog
$FileDialog.Filter = "JSON files (*.json)|*.json"


# Define the GIT connection information, If the Repo is private.
# ------------------------------------------------------------
if (-NOT (Test-Path -Path "$RootPath\GitHub-Connection.json")) {
    $FileDialog.Title  = "Select GIThub secrets file"
    if ($FileDialog.ShowDialog() -eq "OK") {
        $GitConnection = Get-Content -Path $FileDialog.FileName | ConvertFrom-Json
    }
    else {
        Write-Warning "No file selected"
        Write-Host "Download and execute `"InfraAsCode/Secrets/Scripts/Create-GitHubConfig.ps1`" and rerun this script"
    }
} else {
    $GitConnection = Get-Content -Path "$RootPath\GitHub-Connection.json" | Convertfrom-Json
}


# Define PVE connection
# ------------------------------------------------------------
if (-NOT (Test-Path -Path "$RootPath\Proxmox-Connection.json")) {
    $FileDialog.Title  = "Select file"
    if ($FileDialog.ShowDialog() -eq "OK") {
        $PVESecret = Get-Content -Path $FileDialog.FileName | ConvertFrom-Json
    }
    else {
        Throw "No file selected"
    }
} else {
    $PVESecret = Get-Content -Path "$RootPath\Proxmox-Connection.json" | Convertfrom-Json
}


# Get the Required Scripts list
# ------------------------------------------------------------
if (-NOT (Test-Path -Path "$RootPath\DeploymentServerFiles.json")) {
    Throw "Required file DeploymentServerFiles.json is missing"
    Write-Host "Please ensure the `"DeploymentServerFiles.json`" file is copied from installation media"
    exit
} else {
    $RequiredScripts = Get-Content -Path "$RootPath\DeploymentServerFiles.json" | Convertfrom-Json
}


<# Main Script #>


# Virtual Directory Name
# ------------------------------------------------------------
$WebLocation  = "Deployment"


# Required for unsigned scripts & modules.
# ------------------------------------------------------------
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force -Confirm:$false


# Prepare Folders
# ------------------------------------------------------------
if (-NOT (Test-Path -Path "$RootPath\Functions")) {
    New-Item -Path "$RootPath\Functions" -ItemType Directory | Out-Null
}
if (-NOT (Test-Path -Path "$RootPath\GIT-Cache")) {
    New-Item -Path "$RootPath\GIT-Cache" -ItemType Directory | Out-Null
}


# Install IIS Service
# ------------------------------------------------------------
# Optional: "Web-IP-Security", "Web-Windows-Auth"
$Features = @("Web-Server",
              "Web-WebServer",
              "Web-Common-Http",
              "Web-Default-Doc",
              "Web-Dir-Browsing",
              "Web-Http-Errors",
              "Web-Static-Content",
              "Web-Http-Redirect",
              "Web-Health",
              "Web-Http-Logging",
              "Web-Performance",
              "Web-Stat-Compression",
              "Web-Mgmt-Tools",
              "Web-Mgmt-Console"
              )
Get-WindowsFeature -name $Features | Install-WindowsFeature | Out-Null


# Get Default Site configuration
# ------------------------------------------------------------
Import-Module WebAdministration -ErrorAction Stop

$DefaultSite  = Get-ChildItem "IIS:\Sites" | Select-Object -First 1
$SiteName     = $DefaultSite.Name
$PhysicalPath = [Environment]::ExpandEnvironmentVariables($DefaultSite.physicalPath)


# Ensure IIS have been installed, and we can find the default site path.
# ------------------------------------------------------------
if ([string]::IsNullOrWhiteSpace($PhysicalPath) -or (-not (Test-Path -Path $PhysicalPath))) {
    throw "Invalid IIS physical path: $PhysicalPath"
}


# Create Virtual Directory
# ------------------------------------------------------------
$FileLocation = Join-Path -Path $PhysicalPath -ChildPath $WebLocation

if (-NOT (Test-Path "$FileLocation")) {
    New-Item -Path "$FileLocation" -ItemType Directory | Out-Null
}

$DeploymentSite = Get-WebVirtualDirectory -Site $DefaultSite.Name -Name $WebLocation -ErrorAction SilentlyContinue
if (-NOT ($DeploymentSite)) {
    New-WebVirtualDirectory -Site $DefaultSite.Name -Name $WebLocation -PhysicalPath "$FileLocation" -Force | Out-Null
}


# Allow Directory Browse
# ------------------------------------------------------------
If (-NOT ((Get-WebConfigurationProperty -Location "$($DefaultSite.Name)/$WebLocation" -filter "/system.webServer/directoryBrowse" -Name enabled).Value)) {
    Set-WebConfigurationProperty -Location "$($DefaultSite.Name)/$Location" -filter "/system.webServer/directoryBrowse" -Name enabled -Value $true
}

# Add FileExtension .PS1
# ------------------------------------------------------------
$StaticContent = Get-WebConfigurationProperty -Location "$($DefaultSite.Name)/$WebLocation" -Filter "system.webServer/staticContent" -Name "."
if (-NOT ($StaticContent.Collection.fileExtension.Contains(".ps1"))) {
    Add-WebConfigurationProperty -Location "$($DefaultSite.Name)/$WebLocation" -Filter "system.webServer/staticContent" -Name "." -Value @{ fileExtension='.ps1'; mimeType='text/plain' }
}


# Git "Clone"
# ------------------------------------------------------------
Invoke-RestMethod -uri "$($GitConnection.Url)/InfraAsCode/zipball/main" -OutFile "$RootPath\GIT-Cache\GIT-Cache.zip"
Expand-Archive -Path "$RootPath\GIT-Cache\GIT-Cache.zip" -DestinationPath "$RootPath\GIT-Cache" -Force


$RequiredScripts | Foreach {
    $Source = Get-ChildItem -Path "$RootPath\GIT-Cache" -Recurse -Filter $(Split-Path -Path $_.RemotePath -Leaf)
    if (-NOT(Test-Path -Path $_.LocalPath)) {
        Write-Host "New Folder $($_.LocalPath)"
        New-Item -Path $_.LocalPath -ItemType Directory -Force | Out-Null
    }
    Write-Host "Move $($Source.FullName) to $($_.LocalPath)"
    Move-Item -Path $Source.FullName -Destination $_.LocalPath -Force
}

# Cleanup Cache
Remove-Item -Path "$RootPath\GIT-Cache" -Recurse -Force


# Import PVE modules
# ------------------------------------------------------------
Get-ChildItem -Path "$RootPath\Functions" | ForEach-Object { Import-Module -Name $_.FullName -Force }


# Connect to PVE Cluster
# ------------------------------------------------------------
$PVEConnect = PVE-Connect -Authkey "$($PVESecret.User)!$($PVESecret.TokenID)=$($PVESecret.Token)" -Hostaddr $($PVESecret.Host)


# Get VM Status
# ------------------------------------------------------------
$VMID        = (Invoke-RestMethod -Uri "$($PVEConnect.PVEAPI)/cluster/resources?type=vm" -Headers $PVEConnect.Headers).data | Where {$_.name -eq $($ENV:ComputerName)}
$VMStatus    = (Invoke-RestMethod -Uri "$($PVEConnect.PVEAPI)/nodes/$($VMID.node)/qemu/$($VMID.VMID)/config" -Headers $PVEConnect.Headers).data


# Remove all Media Drives
# ------------------------------------------------------------
$MediaDrives = $VMStatus.PSObject.Properties | Where {$_.value -like "*media=cdrom*"} # -and $_.Value -NotLike "*Server*"}

if ($null -ne $MediaDrives) {

    $body = ""
    $MediaDrives | Foreach { $body += "delete=$($_.Name)&" }
    $RemoveMedia = Invoke-RestMethod -Method POST -Uri "$($PVEConnect.PVEAPI)/nodes/$($VMID.node)/qemu/$($VMID.VMID)/config" -Headers $($PVEConnect.Headers) -Body $Body
}


# Enable HA (Autostart)
# ------------------------------------------------------------
$HAStatus = (Invoke-RestMethod -Uri "$($PVEConnect.PVEAPI)/cluster/ha/resources" -Headers $PVEConnect.Headers -Method Get).data
if (-NOT ($HAStatus.data | Where { $_.SID -eq "vm:$($VMID.VMID)" } )) {
    $Body = "sid=$($VMID.VMID)&failback=0&max_relocate=0&state=started"
    $null = Invoke-RestMethod -Uri "$($PVEConnect.PVEAPI)/cluster/ha/resources" -Headers $PVEConnect.Headers -Method Post -Body $Body
}



# Add .... to autostart after reboot.
<#
1. Create template. (C:\Scripts\New-PVEVMTemplate.ps1)
2. Create VM list.  (C:\Scripts\Tools\BuildConfigFiles.ps1)
3. Create Servers.  (C:\Scripts\Create-PVEServers.ps1)
#>


# Shutdown to activate Hardware changes.
# - the HA will restart the server
# ------------------------------------------------------------
Shutdown -p -f


# Disable HA, if wanted.
# ------------------------------------------------------------
#Invoke-RestMethod -Uri "$($PVEConnect.PVEAPI)/cluster/ha/resources/$($VMID.VMID)" -Headers $PVEConnect.Headers -Method Delete
