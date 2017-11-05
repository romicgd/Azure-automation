Param
(
	[Parameter (Mandatory= $true)]
	[String] $workspaceresourcegroup,

	[Parameter (Mandatory= $true)]
	[String] $workspacename
)

$Conn = Get-AutomationConnection -Name AzureRunAsConnection
Add-AzureRMAccount -ServicePrincipal -Tenant $Conn.TenantID `
-ApplicationId $Conn.ApplicationID -CertificateThumbprint $Conn.CertificateThumbprint

$workspace=Get-AzureRmOperationalInsightsWorkspace -Name $workspacename -ResourceGroupName $workspaceresourcegroup 
$workspaceId = $workspace.CustomerId
$workspaceKey = (Get-AzureRmOperationalInsightsWorkspaceSharedKeys -ResourceGroupName $workspace.ResourceGroupName -Name $workspace.Name).PrimarySharedKey

$vms = Get-AzureRmVM  

$PublicSettings = @{"workspaceId" = $workspaceId}
$ProtectedSettings = @{"workspaceKey" = $workspaceKey}

foreach ($vm in $vms) { 
   write-output $vm.name
   $location = $vm.Location
   $vmdet = Get-AzureRMVM -VMname $vm.Name -ResourceGroupName $vm.resourcegroupname -Status
   $vmpowerstatus = $vmdet.Statuses.Code | Where-Object {$_ -Match 'PowerState'}
   if ($vmpowerstatus -eq 'PowerState/running') { 
		if ($vm.StorageProfile.OsDisk.OsType -eq 'Windows') {
            # re-read the VM to get extensiohn name and type populated
            $vm = Get-AzureRMVM -VMname $vm.Name -ResourceGroupName $vm.resourcegroupname
			$extension = ($vm.extensions | where-object {$_.VirtualMachineExtensionType -match "MicrosoftMonitoringAgent"} )
            write-output "Extension found $($extension.Name)"
			if ($extension) {
				$extdet = Get-AzureRMVMExtension -VMname $vm.Name -ResourceGroupName $vm.resourcegroupname -Name $extension.Name
				if($extension.Name -eq 'OMSExtension') {
                    $current_workspace = $extdet.PublicSettings.Split([Environment]::NewLine)[2];
					if ($current_workspace.contains($workspaceId)) {
    					write-output "$($vmdet.name) - is already in the correct workspace [$workspacename]"	
					    continue; /* Move to next VM processing. */ 
					} else {
                        write-output "$$($vmdet.name) - current workspace [$current_workspace]. Need [$workspaceId]"
                    }
                }    
				write-output "$$($vmdet.name) - removing MicrosoftMonitoringAgent extention with name $($extension.Name) and workspace [$current_workspace]"
				Remove-AzureRMVMExtension -VMname $vm.name -ResourceGroupName $vm.resourcegroupname -Name $extension.Name -force
			}
            <#
            	Now we have running Windows VM without OMS extension. 
                Lets attach VM to correct workspace. 
            #>                
			Set-AzureRMVMExtension -VMname $vm.name -ResourceGroupName $vm.resourcegroupname -Publisher 'Microsoft.EnterpriseCloud.Monitoring' -ExtensionType "MicrosoftMonitoringAgent" -ExtensionName 'OMSExtension' -TypeHandlerVersion 1.0 -Settings $PublicSettings -ProtectedSettings $ProtectedSettings -Location $location 
		} else {
			write-output "$($vmdet.name) - non-Windows [$($vm.StorageProfile.OsDisk.OsType)]"
		}
	} else {
			write-output "$($vmdet.name) - not running. VM status[$vmpowerstatus]"
	}	
}
