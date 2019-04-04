function Add-AppGatewayBackendWithMultiSiteHosting {
    <#
 .SYNOPSIS
   This function add an endpoint (application/or IaaS) to existing Application Gateway. 
   
   Notes:
     Backend authetication certificate is the default SNI certificate returned by the site (i.e. https://127.0.0.1) 
     https://docs.microsoft.com/en-us/azure/application-gateway/application-gateway-end-to-end-ssl-powershell 
   Assumptions:
     Incoming protocol is https.
 .EXAMPLE
    Add-BackendWithMultiSiteHosting -Bindings $Bindings -ResourceGroup $env:ApplicationGatewayResourceGroup -AppGwName $env:ApplicationGatewayName `
    -appName $env:WebAppName -appFQDN $env:FrontFQDN -frontendPort $env:frontendPort `
    -pfxFilePath ./sslCertificate.pfx -pfxPassword $env:pfxPassword -CertificatePath ./authenticationCertificate.cer `
    -BackendFqdns $env:BackendFqdns -backendPort $env:backendPort -backendProtocol $env:backendProtocol

 #>
    Param (
        [Parameter(Mandatory = $true)]
        [string]$ResourceGroup,
        [Parameter(Mandatory = $true)]
        [string]$AppGwName,
        [Parameter(Mandatory = $true)]
        [string]$appName,
        [Parameter(Mandatory = $true)]
        [string]$appFQDN,
        [Parameter(Mandatory = $true)]
        [string]$pfxFilePath,
        [Parameter(Mandatory = $true)]
        [string]$pfxPassword,
        [Parameter(Mandatory = $true)]
        [string]$CertificatePath,
        [Parameter(Mandatory = $true)]
        [string]$frontendPort,
        [Parameter(Mandatory = $true)]
        [string]$BackendFqdns,
        [Parameter(Mandatory = $false)]
        [string]$backendHostHeader,
        [Parameter(Mandatory = $true)]
        [string]$backendPort,
        [Parameter(Mandatory = $true)]
        [string]$backendProtocol,
        [Parameter(Mandatory = $false)]
        [string]$probePath = "/"
    )
 
    # names for App GW Components
    $frontEndPortName = "frontendPort_$frontendPort"
    $frontEndIPConfigName = "appGatewayFrontendIP"
    $appGwHttpsListenerName = "Listener_${appName}_${frontendPort}"
    $appHealthProbeName = "healthProbe_${appname}_${backendPort}"
    $backendPoolName = "backEndPool_${appname}_${backendPort}"
    $HttpSettingsName = "HttpSettings_${appname}_${backendPort}"
    $httpsRuleName = "Rule_${appname}_${frontendPort}"
    
    $AppGw = Get-AzureRmApplicationGateway -Name $AppGwName -ResourceGroupName $ResourceGroup

    $Certificates = Set-ITSAzAppGatewayCertificates -ApplicationGateway $AppGw -ApplicationName $appName `
        -PfxFilePath $PfxFilePath -PfxPassword $PfxPassword `
        -CertificatePath $CertificatePath
    $AGBECert = $Certificates.BackendCertificate
    $AGFECert = $Certificates.FrontendCertificate

    if (-not $backendHostHeader) {
        # default is backward compatible for existing clients
        $backendHostHeader = $appFQDN
    }

    # any error on getting just continue and try to create
    try {
        $AGFEPort = Get-AzureRmApplicationGatewayFrontendPort -ApplicationGateway $AppGw -Name $frontEndPortName
    }
    catch {}
    if (-not $AGFEPort) {
        Add-AzureRmApplicationGatewayFrontendPort -ApplicationGateway $AppGw -Name $frontEndPortName -Port $frontendPort
        $AGFEPort = Get-AzureRmApplicationGatewayFrontendPort -ApplicationGateway $AppGw -Name $frontEndPortName
    }
    
    $AGFEIPConfig = Get-AzureRmApplicationGatewayFrontendIPConfig -ApplicationGateway $AppGw -Name $frontEndIPConfigName -ErrorAction Stop
    
    try {
        $AGHttpsListener = Get-AzureRmApplicationGatewayHttpListener -ApplicationGateway $AppGW -Name $appGwHttpsListenerName -ErrorAction Stop
    }
    catch {}
    if (-not $AGHttpsListener) {
        Add-AzureRmApplicationGatewayHttpListener -ApplicationGateway $AppGW -Name $appGwHttpsListenerName -Protocol Https -FrontendIPConfiguration $AGFEIPConfig `
            -FrontendPort $AGFEPort  -SslCertificate $AGFECert -HostName $appFQDN | Out-Null
        $AGHttpsListener = Get-AzureRmApplicationGatewayHttpListener -ApplicationGateway $AppGW -Name $appGwHttpsListenerName
    }
    
    ### BackEnd Pool
    try {
        $AGBEP = Get-AzureRmApplicationGatewayBackendAddressPool -ApplicationGateway $AppGW -Name $backendPoolName -ErrorAction Stop
    }
    catch {}
    if (-not $AGBEP) {
        Add-AzureRmApplicationGatewayBackendAddressPool -ApplicationGateway $AppGW -Name $backendPoolName -BackendFqdns $BackendFqdns | Out-Null
        $AGBEP = Get-AzureRmApplicationGatewayBackendAddressPool -ApplicationGateway $AppGW -Name $backendPoolName -ErrorAction Stop
    }
    
    ### Health Probe
    $probeProperties = @{
        ApplicationGateway = $AppGw
        Name               = $appHealthProbeName
        Path               = $probePath
        Interval           = 30
        Timeout            = 60
        UnhealthyThreshold = 3
        HostName           = $BackendFqdns
        Match              = (New-AzureRmApplicationGatewayProbeHealthResponseMatch -StatusCode "200-401")
    }
    if ($backendProtocol.tolower() -eq "https") {
        $probeProperties["Protocol"] = "https"
    }
    else {
        $probeProperties["Protocol"] = "http"
    }

    try {
        $AGProbe = Get-AzureRmApplicationGatewayProbeConfig -ApplicationGateway $AppGW -name $appHealthProbeName -ErrorAction Stop
    }
    catch {}
    if (-not $AGProbe) {
        Add-AzureRmApplicationGatewayProbeConfig @probeProperties | Out-Null  
    }
    else {
        Set-AzureRmApplicationGatewayProbeConfig @probeProperties | Out-Null   
    }   
    $AGProbe = Get-AzureRmApplicationGatewayProbeConfig -ApplicationGateway $AppGW -Name $appHealthProbeName -ErrorAction Stop

    ### HTTP Settings
    $httpSettingsProperties = @{
        ApplicationGateway  = $AppGw
        Name                = $HttpSettingsName
        Port                = $BackendPort
        Protocol            = $BackendProtocol
        CookieBasedAffinity = "disabled"
        Probe               = $AGProbe
        HostName            = $backendHostHeader
    }
    if ($BackendProtocol -ieq "https") {
        $httpSettingsProperties["AuthenticationCertificates"] = $AGBECert
    }
    try {
        $AGHttpSettings = Get-AzureRmApplicationGatewayBackendHttpSettings -ApplicationGateway $AppGW -Name $HttpSettingsName -ErrorAction Stop
    }
    catch {}
    if (-not $AGHttpSettings) {
        Add-AzureRmApplicationGatewayBackendHttpSettings @httpSettingsProperties | Out-Null
    }
    else {
        Set-AzureRmApplicationGatewayBackendHttpSettings @httpSettingsProperties | Out-Null
    }     
    $AGHttpSettings = Get-AzureRmApplicationGatewayBackendHttpSettings -ApplicationGateway $AppGW -Name $HttpSettingsName
    
    try {
        $routingRule = Get-AzureRmApplicationGatewayRequestRoutingRule  -ApplicationGateway $appgw  -Name $httpsRuleName -ErrorAction Stop
    }
    catch {}
    if (-not $routingRule) {
        Add-AzureRmApplicationGatewayRequestRoutingRule  -ApplicationGateway $appgw -Name $httpsRuleName -RuleType basic `
            -HttpListener $AGHttpsListener -BackendAddressPool $AGBEP -BackendHttpSettings $AGHttpSettings | Out-Null
    }
    else {
        Set-AzureRmApplicationGatewayRequestRoutingRule -ApplicationGateway $appgw -Name $httpsRuleName -RuleType basic `
            -HttpListener $AGHttpsListener -BackendAddressPool $AGBEP -BackendHttpSettings $AGHttpSettings | Out-Null
    }
    Set-AzureRmApplicationGateway -ApplicationGateway $AppGw | Out-Null
}

function Set-ITSAzAppGatewayCertificates {
    <#
 .SYNOPSIS
    
 .EXAMPLE
    #>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true)]
        [object]$ApplicationGateway,
        [Parameter(Mandatory = $true)]
        [string]$ApplicationName,
        [Parameter(Mandatory = $false)]
        [string]$PathName,
        [Parameter(Mandatory = $true)]
        [string]$PfxFilePath,
        [Parameter(Mandatory = $true)]
        [string]$PfxPassword,
        [Parameter(Mandatory = $false)]
        [string]$CertificatePath,
        [Parameter(Mandatory = $false)]
        [switch]$ResolveCertificate,
        [Parameter(Mandatory = $false)]
        [string]$ResolveUrl
    )
    if ($ResolveCertificate) {
        $Certificate = Get-ITSAzWebsiteCertificate -Uri $ResolveUrl -UseSystemProxy -UseDefaultCredentials -TrustAllCertificates
        $CertificateBytes = $Certificate.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Cert)
        $CertificateBase64 = [System.Convert]::ToBase64String($CertificateBytes)
        $CertificatePath = [System.IO.Path]::GetTempFileName()
        $CertificateBase64 | Out-File -FilePath $CertificatePath
    }
    if (-not $CertificatePath) {
        Write-ITSAzLog -Level "Error" -Message "Either CertificatePath needs to be provided, or -ResolveCertificate specified"
        return
    }

    $Certificate = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2
    $CertificateBase64 = Get-Content $CertificatePath
    $Certificate.Import([Convert]::FromBase64String($CertificateBase64))
    $existingCertificates = Get-AzureRmApplicationGatewayAuthenticationCertificate -ApplicationGateway $ApplicationGateway
    foreach ($agwCert in $existingCertificates) {
        $CertObj = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2
        $CertObj.Import([Convert]::FromBase64String($agwCert.Data))
        if ($Certificate.Thumbprint -ieq $CertObj.Thumbprint) {
            Write-ITSAzLog -Level "Info" -Message "Using existing certificate $($agwCert.Name) - $($CertObj.Subject)"
            $BackendCertificate = $agwCert
        }   
    }
    if (-not $BackendCertificate) {
        $Subject = $Certificate.Subject.split(',')[0]
        $Subject = $Subject -replace "CN=", ""
        $Subject = $Subject -replace "\*", "star"
        $Subject = $Subject -replace "\.", "_"
        $CertificateName = "BackEndCertificate_$Subject"
        Add-AzureRmApplicationGatewayAuthenticationCertificate -ApplicationGateway $ApplicationGateway -Name $CertificateName `
            -CertificateFile $CertificatePath | Out-Null
        $BackendCertificate = Get-AzureRmApplicationGatewayAuthenticationCertificate -ApplicationGateway $ApplicationGateway `
            -Name $CertificateName -ErrorAction Stop
    }

    ## FrontendCertificateManagement
    $FrontEndCertName = "FrontEndCertificate_${ApplicationName}"
    $CertPassword = ConvertTo-SecureString -String $PfxPassword  -AsPlainText -Force
    try {
        $FrontendCertificate = Get-AzureRmApplicationGatewaySslCertificate -ApplicationGateway $ApplicationGateway -Name $FrontEndCertName -ErrorAction Stop
    }
    catch {}
    if (-not $FrontendCertificate) {
        Add-AzureRmApplicationGatewaySslCertificate -ApplicationGateway $ApplicationGateway -Name $FrontEndCertName -CertificateFile $PfxFilePath -Password $CertPassword | Out-Null
        $FrontendCertificate = Get-AzureRmApplicationGatewaySslCertificate -ApplicationGateway $ApplicationGateway -Name $FrontEndCertName -ErrorAction Stop
    }

    return New-Object PSObject -Property @{
        BackendCertificate  = $BackendCertificate
        FrontendCertificate = $FrontendCertificate
    }
} 


function Add-BackEndWithPathBasedRouting {
  <#
 .SYNOPSIS
   This function add endpoints (application/or IaaS) with path-based routing. 
   PLEASE NOTE tat this moment this is very much WIP - the current state is "seems to work" :)
   posting so that it may save some time folks who facing similar issues but please USE-AT-YOUR-OWN-RISK

 .EXAMPLE
$urlPathMap= @{}
$gdrtest2ist=@{ certificatePath="....\gdrtest2.cer"; BackendFqdns="gdrtest2..."; Path="/two"}
$gdrtest4ist=@{ certificatePath="...\gdrtest4.cer"; BackendFqdns="gdrtest4..."; Path="/four"}
$urlPathMap.Add("gdrtest2ist", $gdrtest2ist)
$urlPathMap.Add("gdrtest4ist", $gdrtest4ist)

Add-BackendToAppplicationGateway ...

 #>
 Param (
 [Parameter(Mandatory=$true)]
 [string]$ResourceGroup,
 [Parameter(Mandatory=$true)]
 [string]$AppGwName,
 [Parameter(Mandatory=$true)]
 [string]$appName,
 [Parameter(Mandatory=$true)]
 [string]$appFQDN,
 [Parameter(Mandatory=$true)]
 [string]$pfxFilePath,
 [Parameter(Mandatory=$true)]
 [string]$pfxPassword,
 [Parameter(Mandatory=$true)]
 [string]$certificatePath,
 [Parameter(Mandatory=$true)]
 [string]$frontendPort,
 [Parameter(Mandatory=$true)]
 [string]$BackendFqdns,
 [Parameter(Mandatory=$true)]
 [string]$backendPort,
 [Parameter(Mandatory=$true)]
 [string]$backendProtocol,
 [Parameter(Mandatory=$false)]
 [hashtable]$urlPathMap
 )
 
   # names for App GW Components
   $certName="FrontEndCertificate_${appname}"
   $publicCertName="BackEndCertificate_${appname}"
   $frontEndPortName="frontendPort_$frontendPort"
   $frontEndIPConfigName="appGatewayFrontendIP"
   $appGwHttpsListenerName="httpsListener_$appName"
   $appHealthProbeName="healthProbe_${appname}"
   $backendPoolName="backEndPool_${appname}"
   $HttpSettingsName="HttpSettings_${appname}"
   $httpsRuleName="httpsRuleName_${appname}"
 
   $certPassword = ConvertTo-SecureString -String $pfxPassword  -AsPlainText -Force
   $AppGw = Get-AzureRmApplicationGateway -Name $AppGwName -ResourceGroupName $ResourceGroup
  
   # any error on getting just continue and try to create
   try {
     $AGFEPort = Get-AzureRmApplicationGatewayFrontendPort -ApplicationGateway $AppGw -Name $frontEndPortName
   } catch {}
   if(-not $AGFEPort) {
     Add-AzureRmApplicationGatewayFrontendPort -ApplicationGateway $AppGw -Name $frontEndPortName -Port $frontendPort
     $AGFEPort = Get-AzureRmApplicationGatewayFrontendPort -ApplicationGateway $AppGw -Name $frontEndPortName
   }
   Add-AzureRmApplicationGatewaySslCertificate -ApplicationGateway $AppGw -Name $certName -CertificateFile $pfxFilePath -Password $certPassword
   $AGFECert = Get-AzureRmApplicationGatewaySslCertificate -ApplicationGateway $AppGW -Name $certName
   $AGFEIPConfig = Get-AzureRmApplicationGatewayFrontendIPConfig -ApplicationGateway $AppGw -Name $frontEndIPConfigName
   Add-AzureRmApplicationGatewayHttpListener -ApplicationGateway $AppGW -Name $appGwHttpsListenerName -Protocol Https -FrontendIPConfiguration $AGFEIPConfig `
     -FrontendPort $AGFEPort  -SslCertificate $AGFECert -HostName $appFQDN
 
   $AGHttpsListener = Get-AzureRmApplicationGatewayHttpListener -ApplicationGateway $AppGW -Name $appGwHttpsListenerName

   ## configure backend pool here
   Add-AzureRmApplicationGatewayBackendAddressPool -ApplicationGateway $AppGW -Name $backendPoolName -BackendFqdns $BackendFqdns
   $AGBEP = Get-AzureRmApplicationGatewayBackendAddressPool -ApplicationGateway $AppGW -Name $backendPoolName 
   Add-AzureRmApplicationGatewayAuthenticationCertificate -ApplicationGateway $AppGW -Name $publicCertName -CertificateFile $certificatePath
   $AGBECert = Get-AzureRmApplicationGatewayAuthenticationCertificate -ApplicationGateway $AppGW -Name $publicCertName
   $healthProbeMatch = New-AzureRmApplicationGatewayProbeHealthResponseMatch -StatusCode "200-401"  
   Add-AzureRmApplicationGatewayProbeConfig -ApplicationGateway $AppGW -name $appHealthProbeName -Protocol Https -Path / -Interval 30 -Timeout 60 -UnhealthyThreshold 3 `
     -HostName $appFQDN -Match $healthProbeMatch
   $probe  = Get-AzureRmApplicationGatewayProbeConfig -ApplicationGateway $AppGW -name $appHealthProbeName  
   
   # AuthenticationCertificates are required for exxternal services (e.g. IaaS) for https but not allowed for http
   if($backendProtocol.tolower() -eq "https") {
     Add-AzureRmApplicationGatewayBackendHttpSettings -ApplicationGateway $AppGW -Name $HttpSettingsName -Port $backendPort -Protocol $backendProtocol `
     -CookieBasedAffinity disabled -AuthenticationCertificates $AGBECert -Probe $probe 
   } else {
     # when $backendProtocol is not https assume http
     Add-AzureRmApplicationGatewayBackendHttpSettings -ApplicationGateway $AppGW -Name $HttpSettingsName -Port $backendPort -Protocol $backendProtocol `
     -CookieBasedAffinity disabled -Probe $probe 
   }
   $AGHTTP = Get-AzureRmApplicationGatewayBackendHttpSettings -ApplicationGateway $AppGW -Name $HttpSettingsName

   if($urlPathMap) {
      # path-based rule     
      $pathRules = New-Object 'System.Collections.Generic.List[Microsoft.Azure.Commands.Network.Models.PSApplicationGatewayPathRule]'
      foreach($path in $urlPathMap.keys) {
        $pathspec = $urlPathMap.$path
        $backendPathPoolName="backEndPool_${path}"        
        $PathHttpSettingsName="HttpSettings_${path}"
        $urlPathMapConfigName="pathMapConfig_${appname}"        
        $PathPublicCertName="BackEndCertificate_${path}"
        $PathHealthProbeName="healthProbe_${path}"

        Add-AzureRmApplicationGatewayAuthenticationCertificate -ApplicationGateway $AppGW -Name $PathPublicCertName -CertificateFile $pathspec.certificatePath
        $PathAGBECert = Get-AzureRmApplicationGatewayAuthenticationCertificate -ApplicationGateway $AppGW -Name $PathPublicCertName
        $healthProbeMatch = New-AzureRmApplicationGatewayProbeHealthResponseMatch -StatusCode "200-401"  
        Add-AzureRmApplicationGatewayProbeConfig -ApplicationGateway $AppGW -name $PathHealthProbeName -Protocol Https -Path / -Interval 30 -Timeout 60 -UnhealthyThreshold 3 `
          -HostName $pathspec.BackendFqdns -Match $healthProbeMatch
        $probe  = Get-AzureRmApplicationGatewayProbeConfig -ApplicationGateway $AppGW -name $PathHealthProbeName  
     
        Add-AzureRmApplicationGatewayBackendHttpSettings -ApplicationGateway $AppGW -Name $PathHttpSettingsName -Port $backendPort -Protocol $backendProtocol `
        -CookieBasedAffinity disabled -AuthenticationCertificates $PathAGBECert -Probe $probe 
        $PathAGHTTP = Get-AzureRmApplicationGatewayBackendHttpSettings -ApplicationGateway $AppGW -Name $PathHttpSettingsName
        Add-AzureRmApplicationGatewayBackendAddressPool -ApplicationGateway $AppGW -Name $backendPathPoolName -BackendFqdns $pathspec.BackendFqdns
        $AGBEPathPool = Get-AzureRmApplicationGatewayBackendAddressPool -ApplicationGateway $AppGW -Name $backendPathPoolName 
        $pathRule = New-AzureRmApplicationGatewayPathRuleConfig -Name $path -Paths $pathspec.Path -BackendAddressPool $AGBEPathPool -BackendHttpSettings $PathAGHTTP
        $pathRules.add($pathrule)
      }
      Add-AzureRmApplicationGatewayUrlPathMapConfig -ApplicationGateway $appgw -Name $urlPathMapConfigName -PathRules $pathRules -DefaultBackendAddressPool  $AGBEP -DefaultBackendHttpSettings $AGHTTP
      $urlPathMapConfig = Get-AzureRmApplicationGatewayUrlPathMapConfig  -ApplicationGateway $appgw  -Name $urlPathMapConfigName
      Add-AzureRmApplicationGatewayRequestRoutingRule  -ApplicationGateway $appgw -Name $httpsRuleName -RuleType PathBasedRouting -HttpListener $AGHttpsListener -UrlPathMap $urlPathMapConfig
   }

   Set-AzureRmApplicationGateway -ApplicationGateway $AppGw
 }

