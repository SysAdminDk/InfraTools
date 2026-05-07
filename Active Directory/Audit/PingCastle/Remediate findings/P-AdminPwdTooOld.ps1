<#

    The purpose is to ensure that all admins are changing their passwords at least every year

    This rule ensure that passwords of administrator are well managed.

#>

# Define max password age.
# --------------------------------------------------
$PasswordAge = (Get-Date).AddMonths(-12)


# Find all Domain Admins that have OLD password
# --------------------------------------------------
$OldAdmis = Get-ADGroupMember "Domain Admins" | Get-ADUser -Properties PasswordLastSet | Where-Object {
    $_.PasswordLastSet -lt $PasswordAge -and $_.Enabled -eq $True
}


Write-Output "Please update password on listed users ASAP"
$OldAdmis | Select-Object Name,PasswordLastSet,DistinguishedName
