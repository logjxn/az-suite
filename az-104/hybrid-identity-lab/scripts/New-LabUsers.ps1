<#
.SYNOPSIS
    Creates Lab OUs, users and groups for the hybrid identity lab
.EXAMPLE
    .\New-LabUsers.ps1 -UpnSuffix tenant.onmicrosoft.com
    (prompts for the password, masked)
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$UpnSuffix,
    [Parameter(Mandatory)]
    [securestring]$InitialPassword
)

$ErrorActionPreference = 'Stop'      # stop at first error
Import-Module ActiveDirectory

$Domain = 'DC=lab,DC=internal'
$Base   = "OU=Lab,$Domain"

# OUs
$OUs = @(
    @{ Name = 'Lab';       Path = $Domain }
    @{ Name = 'Users';     Path = $Base }
    @{ Name = 'Groups';    Path = $Base }
    @{ Name = 'Computers'; Path = $Base }
)

foreach ($ou in $OUs) {
    $dn = "OU=$($ou.Name),$($ou.Path)"
    if (Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$dn'") {
        Write-Host "skip  OU     $dn"
        continue
    }
    New-ADOrganizationalUnit -Name $ou.Name -Path $ou.Path
    Write-Host "made  OU     $dn"
}

# Users
$Users = @(
    @{ Given = 'Jane'; Sur = 'Doe';     Sam = 'jdoe' }
    @{ Given = 'Lee';  Sur = 'Gu';      Sam = 'lgu' }
    @{ Given = 'Goku'; Sur = 'Kakarot'; Sam = 'gkakarot' }
    @{ Given = 'SOA';  Sur = 'Test';    Sam = 'soa.test' }   # throwaway for later lab step
)

foreach ($u in $Users) {
    $sam      = $u.Sam
    $fullName = "$($u.Given) $($u.Sur)"

    $existing = Get-ADUser -Filter "SamAccountName -eq '$sam' -or Name -eq '$fullName'"
    if ($existing) {
        if ($existing.SamAccountName -eq $sam) {
            Write-Host "skip  user   $sam"
            continue
        }
        throw "Name '$fullName' is already used by '$($existing.SamAccountName)'. Fix the user list or remove that account."
    }

    $userParams = @{
        Name                  = $fullName
        GivenName             = $u.Given
        Surname               = $u.Sur
        DisplayName           = $fullName
        SamAccountName        = $sam
        UserPrincipalName     = "$sam@$UpnSuffix"
        Path                  = "OU=Users,$Base"
        AccountPassword       = $InitialPassword
        Enabled               = $true
        ChangePasswordAtLogon = $false   # need the known password for lab
    }
    New-ADUser @userParams
    Write-Host "made  user   $sam@$UpnSuffix"
}

# Groups
$GroupName = 'GG-Lab-Readers'
$Members   = @('jdoe', 'lgu', 'gkakarot') 

if (Get-ADGroup -Filter "Name -eq '$GroupName'") {
    Write-Host "skip  group  $GroupName"
} else {
    New-ADGroup -Name $GroupName -GroupScope Global -GroupCategory Security -Path "OU=Groups,$Base"
    Write-Host "made  group  $GroupName"
}

# Users that aren't in
$current = Get-ADGroupMember -Identity $GroupName | Select-Object -ExpandProperty SamAccountName
$toAdd   = $Members | Where-Object { $_ -notin $current }
if ($toAdd) {
    Add-ADGroupMember -Identity $GroupName -Members $toAdd
    Write-Host "added to $GroupName : $($toAdd -join ', ')"
} else {
    Write-Host "skip  members (all already in $GroupName)"
}