 $apps=(get-AzureADApplication -All $true )
 foreach($app in $apps) {
	$appid = "'"+$app.appid+"'"; 
	foreach($requiredResourceAccess in $app.requiredresourceaccess) {
		$resourceAppId = $requiredResourceAccess.resourceAppId 
		$resourceappid = "'"+$resourceAppId+"'"; 
		$resourcesp=(get-azureADServicePrincipal -Filter "AppId eq $resourceappid"); 
		foreach($approle in $resourcesp.Oauth2Permissions) {
			foreach($resourceaccess in $requiredResourceAccess.resourceAccess) {
				if (($approle.id -eq $resourceAccess.id) -and ($resourceAccess.type -eq 'Scope')) {
					Write-output "$appid,$($app.displayname),$resourceappid,$($resourcesp.DisplayName),$($approle.Value)" | out-file ".\delegatedprivs-all.txt" -append
				}
			}
		}	
		foreach($approle in $resourcesp.AppRoles) {
			foreach($resourceaccess in $requiredResourceAccess.resourceAccess) {
				if (($approle.id -eq $resourceAccess.id) -and ($resourceAccess.type -eq 'Role')) {
					Write-output "$appid,$($app.displayname),$resourceappid,$($resourcesp.DisplayName),$($approle.Value)" | out-file ".\appprivs-all.txt" -append
				}
			}
		}	
	}	
 }
