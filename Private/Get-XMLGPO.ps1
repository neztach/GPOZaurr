﻿function Get-XMLGPO {
    [cmdletBinding()]
    param(
        [XML] $XMLContent,
        [Microsoft.GroupPolicy.Gpo] $GPO,
        [switch] $PermissionsOnly,
        [switch] $OwnerOnly,
        [System.Collections.IDictionary] $ADAdministrativeGroups,
        [string] $Splitter = [System.Environment]::NewLine
    )
    if ($XMLContent.GPO.LinksTo) {
        $LinkSplit = ([Array] $XMLContent.GPO.LinksTo).Where( { $_.Enabled -eq $true }, 'Split')
        [Array] $LinksEnabled = $LinkSplit[0]
        [Array] $LinksDisabled = $LinkSplit[1]
        $LinksEnabledCount = $LinksEnabled.Count
        $LinksDisabledCount = $LinksDisabled.Count
        $LinksTotalCount = ([Array] $XMLContent.GPO.LinksTo).Count
        if ($LinksEnabledCount -eq 0) {
            $Linked = $false
        } else {
            $Linked = $true
        }
    } else {
        $Linked = $false
        $LinksEnabledCount = 0
        $LinksDisabledCount = 0
        $LinksTotalCount = 0
    }
    if ($null -eq $XMLContent.GPO.Computer.ExtensionData -and $null -eq $XMLContent.GPO.User.ExtensionData) {
        $Empty = $true
    } else {
        $Empty = $false
    }


    # Find proper values for enabled/disabled user/computer settings
    if ($XMLContent.GPO.Computer.Enabled -eq 'False') {
        $ComputerEnabled = $false
    } elseif ($XMLContent.GPO.Computer.Enabled -eq 'True') {
        $ComputerEnabled = $true
    }
    if ($XMLContent.GPO.User.Enabled -eq 'False') {
        $UserEnabled = $false
    } elseif ($XMLContent.GPO.User.Enabled -eq 'True') {
        $UserEnabled = $true
    }
    # Translate Enabled to same as GPO GUI
    if ($UserEnabled -eq $True -and $ComputerEnabled -eq $true) {
        $Enabled = 'Enabled'
    } elseif ($UserEnabled -eq $false -and $ComputerEnabled -eq $false) {
        $Enabled = 'All settings disabled'
    } elseif ($UserEnabled -eq $true -and $ComputerEnabled -eq $false) {
        $Enabled = 'Computer configuration settings disabled'
    } elseif ($UserEnabled -eq $false -and $ComputerEnabled -eq $true) {
        $Enabled = 'User configuration settings disabled'
    }

    $ComputerSettingsAvailable = if ($null -eq $XMLContent.GPO.Computer.ExtensionData) { $false } else { $true }
    $UserSettingsAvailable = if ($null -eq $XMLContent.GPO.User.ExtensionData) { $false } else { $true }

    $ComputerProblem = $false
    if ($ComputerEnabled -eq $true -and $ComputerSettingsAvailable -eq $true) {
        $ComputerOptimized = $true
    } elseif ($ComputerEnabled -eq $true -and $ComputerSettingsAvailable -eq $false) {
        $ComputerOptimized = $false
    } elseif ($ComputerEnabled -eq $false -and $ComputerSettingsAvailable -eq $false) {
        $ComputerOptimized = $true
    } else {
        # Enabled $false, but ComputerData is there.
        $ComputerOptimized = $false
        $ComputerProblem = $true
    }

    $UserProblem = $false
    if ($UserEnabled -eq $true -and $UserSettingsAvailable -eq $true) {
        $UserOptimized = $true
    } elseif ($UserEnabled -eq $true -and $UserSettingsAvailable -eq $false) {
        $UserOptimized = $false
    } elseif ($UserEnabled -eq $false -and $UserSettingsAvailable -eq $false) {
        $UserOptimized = $true
    } else {
        # Enabled $false, but UserData is there.
        $UserOptimized = $false
        $UserProblem = $true
    }

    if (-not $PermissionsOnly) {
        if ($XMLContent.GPO.SecurityDescriptor.Owner.Name.'#text') {
            $AdministrativeGroup = $ADAdministrativeGroups['ByNetBIOS']["$($XMLContent.GPO.SecurityDescriptor.Owner.Name.'#text')"]
            $WellKnown = ConvertFrom-SID -SID $XMLContent.GPO.SecurityDescriptor.Owner.SID.'#text' -OnlyWellKnown
            if ($AdministrativeGroup) {
                $OwnerType = 'Administrative'
            } elseif ($WellKnown.Name) {
                $OwnerType = 'WellKnown'
            } else {
                $OwnerType = 'NotAdministrative'
            }
        } else {
            $OwnerType = 'Unknown'
        }
    }
    if ($PermissionsOnly) {
        [PsCustomObject] @{
            'DisplayName'          = $XMLContent.GPO.Name
            'DomainName'           = $XMLContent.GPO.Identifier.Domain.'#text'
            'GUID'                 = $XMLContent.GPO.Identifier.Identifier.InnerText -replace '{' -replace '}'
            'Enabled'              = $Enabled
            'Name'                 = $XMLContent.GPO.SecurityDescriptor.Owner.Name.'#text'
            'Sid'                  = $XMLContent.GPO.SecurityDescriptor.Owner.SID.'#text'
            #'SidType'        = if (($XMLContent.GPO.SecurityDescriptor.Owner.SID.'#text').Length -le 10) { 'WellKnown' } else { 'Other' }
            'PermissionType'       = 'Allow'
            'Inherited'            = $false
            'Permissions'          = 'Owner'
            'GPODistinguishedName' = $GPO.Path
        }
        $XMLContent.GPO.SecurityDescriptor.Permissions.TrusteePermissions | ForEach-Object -Process {
            if ($_) {
                [PsCustomObject] @{
                    'DisplayName'          = $XMLContent.GPO.Name
                    'DomainName'           = $XMLContent.GPO.Identifier.Domain.'#text'
                    'GUID'                 = $XMLContent.GPO.Identifier.Identifier.InnerText -replace '{' -replace '}'
                    'Enabled'              = $Enabled
                    'Name'                 = $_.trustee.name.'#Text'
                    'Sid'                  = $_.trustee.SID.'#Text'
                    #'SidType'        = if (($XMLContent.GPO.SecurityDescriptor.Owner.SID.'#text').Length -le 10) { 'WellKnown' } else { 'Other' }
                    'PermissionType'       = $_.type.PermissionType
                    'Inherited'            = if ($_.Inherited -eq 'false') { $false } else { $true }
                    'Permissions'          = $_.Standard.GPOGroupedAccessEnum
                    'GPODistinguishedName' = $GPO.Path
                }
            }
        }
    } elseif ($OwnerOnly) {
        [PsCustomObject] @{
            'DisplayName'          = $XMLContent.GPO.Name
            'DomainName'           = $XMLContent.GPO.Identifier.Domain.'#text'
            'GUID'                 = $XMLContent.GPO.Identifier.Identifier.InnerText -replace '{' -replace '}'
            'Enabled'              = $Enabled
            'Owner'                = $XMLContent.GPO.SecurityDescriptor.Owner.Name.'#text'
            'OwnerSID'             = $XMLContent.GPO.SecurityDescriptor.Owner.SID.'#text'
            'OwnerType'            = $OwnerType
            'GPODistinguishedName' = $GPO.Path
        }
    } else {
        [PsCustomObject] @{
            'DisplayName'                       = $XMLContent.GPO.Name
            'DomainName'                        = $XMLContent.GPO.Identifier.Domain.'#text'
            'GUID'                              = $XMLContent.GPO.Identifier.Identifier.InnerText -replace '{' -replace '}'
            'Empty'                             = $Empty
            'Linked'                            = $Linked
            'LinksCount'                        = $LinksTotalCount
            'LinksEnabledCount'                 = $LinksEnabledCount
            'LinksDisabledCount'                = $LinksDisabledCount
            'Enabled'                           = $Enabled
            'ComputerEnabled'                   = $ComputerEnabled
            'ComputerOptimized'                 = $ComputerOptimized
            'ComputerProblem'                   = $ComputerProblem
            'UserEnabled'                       = $UserEnabled
            'UserOptimized'                     = $UserOptimized
            'UserProblem'                       = $UserProblem
            'ComputerSettingsAvailable'         = $ComputerSettingsAvailable
            'UserSettingsAvailable'             = $UserSettingsAvailable
            'ComputerSettingsStatus'            = if ($XMLContent.GPO.Computer.VersionDirectory -eq 0 -and $XMLContent.GPO.Computer.VersionSysvol -eq 0) { "NeverModified" } else { "Modified" }
            'ComputerSetttingsVersionIdentical' = if ($XMLContent.GPO.Computer.VersionDirectory -eq $XMLContent.GPO.Computer.VersionSysvol) { $true } else { $false }
            'ComputerSettings'                  = $XMLContent.GPO.Computer.ExtensionData.Extension
            'UserSettingsStatus'                = if ($XMLContent.GPO.User.VersionDirectory -eq 0 -and $XMLContent.GPO.User.VersionSysvol -eq 0) { "NeverModified" } else { "Modified" }
            'UserSettingsVersionIdentical'      = if ($XMLContent.GPO.User.VersionDirectory -eq $XMLContent.GPO.User.VersionSysvol) { $true } else { $false }
            'UserSettings'                      = $XMLContent.GPO.User.ExtensionData.Extension
            'ComputerPolicies'                  = $XMLContent.GPO.Computer.ExtensionData.Name -join ", "
            'UserPolicies'                      = $XMLContent.GPO.User.ExtensionData.Name -join ", "
            'CreationTime'                      = [DateTime] $XMLContent.GPO.CreatedTime
            'ModificationTime'                  = [DateTime] $XMLContent.GPO.ModifiedTime
            'ReadTime'                          = [DateTime] $XMLContent.GPO.ReadTime
            'WMIFilter'                         = $GPO.WmiFilter.name
            'WMIFilterDescription'              = $GPO.WmiFilter.Description
            'GPODistinguishedName'              = $GPO.Path
            'SDDL'                              = if ($Splitter -ne '') { $XMLContent.GPO.SecurityDescriptor.SDDL.'#text' -join $Splitter } else { $XMLContent.GPO.SecurityDescriptor.SDDL.'#text' }
            'Owner'                             = $XMLContent.GPO.SecurityDescriptor.Owner.Name.'#text'
            'OwnerSID'                          = $XMLContent.GPO.SecurityDescriptor.Owner.SID.'#text'
            'OwnerType'                         = $OwnerType
            'ACL'                               = @(
                [PsCustomObject] @{
                    'Name'           = $XMLContent.GPO.SecurityDescriptor.Owner.Name.'#text'
                    'Sid'            = $XMLContent.GPO.SecurityDescriptor.Owner.SID.'#text'
                    'PermissionType' = 'Allow'
                    'Inherited'      = $false
                    'Permissions'    = 'Owner'
                }
                $XMLContent.GPO.SecurityDescriptor.Permissions.TrusteePermissions | ForEach-Object -Process {
                    if ($_) {
                        [PsCustomObject] @{
                            'Name'           = $_.trustee.name.'#Text'
                            'Sid'            = $_.trustee.SID.'#Text'
                            'PermissionType' = $_.type.PermissionType
                            'Inherited'      = if ($_.Inherited -eq 'false') { $false } else { $true }
                            'Permissions'    = $_.Standard.GPOGroupedAccessEnum
                        }
                    }
                }
            )
            'Auditing'                          = if ($XMLContent.GPO.SecurityDescriptor.AuditingPresent.'#text' -eq 'true') { $true } else { $false }
            'Links'                             = @(
                $XMLContent.GPO.LinksTo | ForEach-Object -Process {
                    if ($_) {
                        $_.SOMPath
                    }
                }
            ) -join $Splitter
            'LinksObjects'                      = $XMLContent.GPO.LinksTo | ForEach-Object -Process {
                if ($_) {
                    [PSCustomObject] @{
                        CanonicalName = $_.SOMPath
                        Enabled       = $_.Enabled
                        NoOverride    = $_.NoOverride
                    }
                }
            }
        }
    }
}