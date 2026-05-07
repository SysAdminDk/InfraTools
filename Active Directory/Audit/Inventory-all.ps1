<#

    Inventory Local Users and GroupsMembers on all Member Servers.

#>


# List all Windows Servers in the domain, excluding Domain Controllers
# ----------------------------------------------------------------------------------------------------
$AllServers = Get-ADComputer -Filter "operatingSystem -like 'Windows Server*' -and Enabled -eq 'True'"
$AllServers = $AllServers | Where {$_.DistinguishedName -Notlike "*Domain Controllers*"}


# Run Inventory
# ----------------------------------------------------------------------------------------------------
Foreach ($Server in $AllServers) {

    # Test connection with WinRM (needed for remote PowerShell)
    # ----------------------------------------------------------------------------------------------------
    $NetWinRM = Test-NetConnection -ComputerName $Server.DNSHostName -CommonTCPPort WINRM
    If (!($NetWinRM.TcpTestSucceeded)) {
        Write-Warning "Unable to connect to $($Server.DNSHostName)"
    } else {

        # Connect and get all Local Users and Group Members
        # ----------------------------------------------------------------------------------------------------
        Write-Output $Server.DNSHostName
        $Inventory = Invoke-Command -ComputerName $Server.DNSHostName -Authentication NegotiateWithImplicitCredential -ScriptBlock {

            $Data = New-Object -TypeName psobject

            $LocalUserData = @()
            Get-LocalUser | Select-Object -Property Name, Enabled, PasswordExpires, PasswordLastSet, PasswordRequired | Foreach {

                $Users = New-Object -TypeName psobject
                $Users | Add-Member -MemberType NoteProperty -Name "UserName" -Value $_.Name
                $Users | Add-Member -MemberType NoteProperty -Name "Enabled" -Value $_.Enabled
                $Users | Add-Member -MemberType NoteProperty -Name "PasswordExpires" -Value $_.PasswordExpires
                $Users | Add-Member -MemberType NoteProperty -Name "PasswordLastSet" -Value $_.PasswordLastSet
                $Users | Add-Member -MemberType NoteProperty -Name "PasswordRequired" -Value $_.PasswordRequired

                $LocalUserData += $Users

            }
            $Data | Add-Member -MemberType NoteProperty -Name UserData -Value $LocalUserData


            $LocalGroupData = @()
            Get-LocalGroup | Foreach {
                $GroupName = $_.Name
                if ($GroupName) {
                    Get-LocalGroupMember $GroupName | Foreach {

                        $Groups = New-Object -TypeName psobject
                        $Groups | Add-Member -MemberType NoteProperty -Name "GroupName" -Value $GroupName
                        $Groups | Add-Member -MemberType NoteProperty -Name "MemberName" -Value $_.Name
                        $Groups | Add-Member -MemberType NoteProperty -Name "Source" -Value $_.PrincipalSource
                        $Groups | Add-Member -MemberType NoteProperty -Name "Class" -Value $_.ObjectClass

                        $LocalGroupData += $Groups
                    }
                }
            }
            $Data | Add-Member -MemberType NoteProperty -Name GroupData -Value $LocalGroupData


            $Command = Get-Command -Name "Get-ScheduledTask" -ErrorAction SilentlyContinue
            if ($Command -eq $null) {

                Write-Warning "$($ENV:Computername) : The PowerShell command `"Get-ScheduledTask`" is not recognized"

            } else {
                $ExcludeAccounts = @($null,"System","Network Service", "local Service")
                $Tasks = Get-ScheduledTask | Select-Object TaskName, State, @{Name="RunAs";Expression={ $_.principal.userid }} | Where {$_.RunAs -notin $ExcludeAccounts}
                if ($Tasks) {
                    $Data | Add-Member -MemberType NoteProperty -Name ScheduledTask -Value $Tasks
                }
            }


            $ExcludeAccounts = @($null,"LocalSystem","NT Authority")
            $Services = Get-CimInstance -query "Select * from WIN32_Service" | Select-Object Name, StartName, @{Name="RunAs"; Expression={ ($_.StartName -split("\\"))[0] }} | Where {$_.RunAs -notin $ExcludeAccounts}
            if ($Services) {
                $Data | Add-Member -MemberType NoteProperty -Name Services -Value $Services
            }

            Return $Data
        }

        $Inventory | ConvertTo-Json -Depth 5 | Out-File -FilePath "C:\Temp\Inventory\$($Server.DNSHostName).json"
    }
}

