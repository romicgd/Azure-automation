function Add-AppRegistrationPermission {
    <#
        .SYNOPSIS

        .NOTES
            The privileges configuration needs to be followed by actual permission grant done my gobal admin account eitehr via Azure CLI, Power Shell(via Rest API) or Azure portal  
            https://docs.microsoft.com/en-us/cli/azure/ad/app/permission?view=azure-cli-latest#az-ad-app-permission-admin-consent
        .EXAMPLE
            Add-AppRegistrationPermission -AppServiceRegistrationName 'your-function-registration-name' -APIName "Windows Azure Active Directory" -requiredDelegatedPermissions "User.Read"
            Add-AppRegistrationPermission -AppServiceRegistrationName 'your-function-registration-name' -APIName "Microsoft Graph" -requiredApplicationPermissions "User.ReadWrite.All Reports.Read.All"
    
    #>
    Param (
            [Parameter(Mandatory=$true)]
            [string]$AppServiceRegistrationName,
            [Parameter(Mandatory=$true)]
            [string]$APIName,
            [Parameter(Mandatory=$false)]
            [string]$requiredApplicationPermissions,
            [Parameter(Mandatory=$false)]
            [string]$requiredDelegatedPermissions 
    )
        $clientApplication = Get-AzureADApplication -Filter ("DisplayName eq '"+$AppServiceRegistrationName+"'")
        # filter in case more than one hAPI matches the search string
        $azureadsp = Get-AzureADServicePrincipal -SearchString $APIName | Where-Object {$_.DisplayName -eq "$APIName"}

        $AzureADGraphRequiredPermissions = GetRequiredPermissions -reqsp $azureadsp -requiredDelegatedPermissions $requiredDelegatedPermissions -requiredApplicationPermissions $requiredApplicationPermissions 
        $requiredResourcesAccess = New-Object System.Collections.Generic.List[Microsoft.Open.AzureAD.Model.RequiredResourceAccess]
        $requiredResourcesAccess.Add($AzureADGraphRequiredPermissions)
        Set-AzureADApplication -ObjectId $clientApplication.ObjectId -RequiredResourceAccess $requiredResourcesAccess
    }
    

Function AddResourcePermission($requiredAccess, $exposedPermissions, $requiredAccesses, $permissionType) {
    foreach ($permission in $requiredAccesses.Trim().Split(" ")) {
        $reqPermission = $null
        $reqPermission = $exposedPermissions | Where-Object {$_.Value -contains $permission}
        Write-Host "Collected information for $($reqPermission.Value) of type $permissionType" -ForegroundColor Green
        $resourceAccess = New-Object Microsoft.Open.AzureAD.Model.ResourceAccess
        $resourceAccess.Type = $permissionType
        $resourceAccess.Id = $reqPermission.Id    
        $requiredAccess.ResourceAccess.Add($resourceAccess)
    }
}
  
Function GetRequiredPermissions($requiredDelegatedPermissions, $requiredApplicationPermissions, $reqsp) {
    $sp = $reqsp
    $appid = $sp.AppId
    $requiredAccess = New-Object Microsoft.Open.AzureAD.Model.RequiredResourceAccess
    $requiredAccess.ResourceAppId = $appid
    $requiredAccess.ResourceAccess = New-Object System.Collections.Generic.List[Microsoft.Open.AzureAD.Model.ResourceAccess]
    if ($requiredDelegatedPermissions) {
        AddResourcePermission $requiredAccess -exposedPermissions $sp.Oauth2Permissions -requiredAccesses $requiredDelegatedPermissions -permissionType "Scope"
    } 
    if ($requiredApplicationPermissions) {
        AddResourcePermission $requiredAccess -exposedPermissions $sp.AppRoles -requiredAccesses $requiredApplicationPermissions -permissionType "Role"
    }
    return $requiredAccess
}
