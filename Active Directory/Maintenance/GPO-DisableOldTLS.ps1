<#

    Will create GPO to Disable Cipher Suites
    Will Link the GPO to Domain Controllers.

    Ref : https://techcommunity.microsoft.com/blog/coreinfrastructureandsecurityblog/schannel-follow-up/259399
    Ref : https://github.com/Crosse/SchannelGroupPolicy
#>

# Create GPO
# ------------------------------------------------------------
$GPOName = "MSFT - Manage Security Providers (SCHANNEL)"
New-Gpo -Name $GPOName | Out-Null
$GPO = Get-GPO -Name $GPOName


# Add "Default" Values
# ------------------------------------------------------------
Set-GPRegistryValue -Name $GPO.DisplayName -Key "HKLM\Software\Policies\Microsoft\Windows\Schannel" -ValueName SchannelServerProtocols -Value 1 -Type DWord | Out-Null
Set-GPRegistryValue -Name $GPO.DisplayName -Key "HKLM\Software\Policies\Microsoft\Windows\Schannel" -ValueName SchannelClientProtocols -Value 1 -Type DWord | Out-Null
Set-GPRegistryValue -Name $GPO.DisplayName -Key "HKLM\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\Multi-Protocol Unified Hello\Client" -ValueName Enabled -Value 0xFFFFFFFF -Type DWord | Out-Null
Set-GPRegistryValue -Name $GPO.DisplayName -Key "HKLM\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\Multi-Protocol Unified Hello\Server" -ValueName Enabled -Value 0xFFFFFFFF -Type DWord | Out-Null
Set-GPRegistryValue -Name $GPO.DisplayName -Key "HKLM\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\PCT 1.0\Client" -ValueName Enabled -Value 0xFFFFFFFF -Type DWord | Out-Null
Set-GPRegistryValue -Name $GPO.DisplayName -Key "HKLM\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\PCT 1.0\Server" -ValueName Enabled -Value 0xFFFFFFFF -Type DWord | Out-Null
Set-GPRegistryValue -Name $GPO.DisplayName -Key "HKLM\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\SSL 2.0\Client" -ValueName Enabled -Value 0xFFFFFFFF -Type DWord | Out-Null
Set-GPRegistryValue -Name $GPO.DisplayName -Key "HKLM\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\SSL 2.0\Server" -ValueName Enabled -Value 0xFFFFFFFF -Type DWord | Out-Null
Set-GPRegistryValue -Name $GPO.DisplayName -Key "HKLM\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\SSL 3.0\Client" -ValueName Enabled -Value 0xFFFFFFFF -Type DWord | Out-Null
Set-GPRegistryValue -Name $GPO.DisplayName -Key "HKLM\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\SSL 3.0\Server" -ValueName Enabled -Value 0xFFFFFFFF -Type DWord | Out-Null
Set-GPRegistryValue -Name $GPO.DisplayName -Key "HKLM\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.0\Client" -ValueName Enabled -Value 0 -Type DWord | Out-Null
Set-GPRegistryValue -Name $GPO.DisplayName -Key "HKLM\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.0\Server" -ValueName Enabled -Value 0 -Type DWord | Out-Null
Set-GPRegistryValue -Name $GPO.DisplayName -Key "HKLM\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.1\Client" -ValueName Enabled -Value 0 -Type DWord | Out-Null
Set-GPRegistryValue -Name $GPO.DisplayName -Key "HKLM\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.1\Server" -ValueName Enabled -Value 0 -Type DWord | Out-Null


# Link to Domain Controllers
# ------------------------------------------------------------
New-GPLink -Name $GPO.DisplayName -Target (Get-ADDomain).DomainControllersContainer | Out-Null
