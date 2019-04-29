function Add-AppServiceIpRestrictionRule {
    <#
      .SYNOPSIS
      Adds IP restrictions to App Service.

      .DESCRIPTION
      Adds IP restrictions to App Service.
      
      .PARAMETER Bindings 

      .EXAMPLE
      Add-AppServiceIpRestrictionRule   -ResourceGroupName '' -AppServiceName '' -AllowedCIDRs $allowerIps
  #>    
    Param
    (
        # Name of the resource group that contains the App Service.
        [Parameter(Mandatory = $true)]
        $ResourceGroupName, 
        # Name of your Web or API App.
        [Parameter(Mandatory = $true)]
        $AppServiceName, 
        # rule to add.
        [Parameter(Mandatory = $true)]
        [string[]]$AllowedCIDRs
    )
 
    $ApiVersions = Get-AzureRmResourceProvider -ProviderNamespace Microsoft.Web |
    Select-Object -ExpandProperty ResourceTypes |
    Where-Object ResourceTypeName -eq 'sites' |
    Select-Object -ExpandProperty ApiVersions
 
    $LatestApiVersion = $ApiVersions[0]

    $priority=0
    $rules=@()
    foreach($cidr in $AllowedCIDRs)  {
        if(-not ($cidr -match "/")) {
            $cidr = $cidr+"/32"
        }
        $rule = [PSCustomObject]@{
            ipAddress = $cidr
            action = "Allow"
            priority = $priority
            name = $cidr
            description = $cidr
        }
        $rules += $rule
        $priority=$priority+1
    }

    $WebAppConfig = Get-AzureRmResource -ResourceType 'Microsoft.Web/sites/config' -ResourceName $AppServiceName -ResourceGroupName $ResourceGroupName -ApiVersion $LatestApiVersion
    $WebAppConfig.Properties.ipSecurityRestrictions = @($rules) 
    Set-AzureRmResource -ResourceId $WebAppConfig.ResourceId -Properties $WebAppConfig.Properties -ApiVersion $LatestApiVersion -Force
}
