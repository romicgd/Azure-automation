function Set-SubscriptionsSQLADAdmin {
<#
    .SYNOPSIS 
        Add Azure AD authentication to Azure SQL in current subscription.
    .DESCRIPTION
        Iterates all Azure SQL in current subscription and add Azure AD authentication if not setup already.
        Better use Active Directory group as opposed to individual so you can manage SQL administrators via membership in this group.
    .EXAMPLE
       Set-SubscriptionsSQLADAdmin -dbaGroupName $dbaGroupName

#>
Param (
    [Parameter(Mandatory = $false)]
    [string]$dbaGroupName
)
    $sqlservers = Get-AzureRmSqlServer
    foreach($sqlserver in $sqlservers) {
        $sqladmin = Get-AzureRmSqlServerActiveDirectoryAdministrator -servername $sqlserver.servername -resourcegroupname $sqlserver.ResourceGroupName
        if(-not $sqladmin) {
            $aadgroup = Get-AzureADGroup -Filter "DisplayName eq '$dbaGroupName'"
            if (-not $aadgroup) {
                Write-Output "Group [$dbaGroupName] not found.Creating."
            } else {
                Write-Output "Group [$dbaGroupName] found."
                $sqladmin = Set-AzureRmSqlServerActiveDirectoryAdministrator -servername $sqlserver.servername -resourcegroupname $sqlserver.ResourceGroupName `
                    -displayName $dbaGroupName
                Write-Output "Active DirectoryADmin Has been set."
            }
        } else {
            Write-Output "Ad Admin for [$($sqlserver.servername)] is [$($sqladmin.Displayname)]"
        }
    }
}
