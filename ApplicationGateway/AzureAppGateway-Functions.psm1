function Add-BackendToAppplicationGateway {
  <#
 .SYNOPSIS
   This function add an endpoint (application/or IaaS) to existing Application Gateway. 
   http://devchat.live/en/2018/07/02/how-to-map-url-path-based-rules-in-application-gateway-for-your-azure-web-app-service/ 

   Notes:
     Backend authetication certificate is the default SNI certificate returned by the site (i.e. https://127.0.0.1) 
     https://docs.microsoft.com/en-us/azure/application-gateway/application-gateway-end-to-end-ssl-powershell 
   Assumptions:
     Incoming protocol is https and certificates are loaded into the keyvault.
 .EXAMPLE

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
 [string]$backendProtocol
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
 
   # configure app gateway
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
   
    # simple rule (not path-based)
   Add-AzureRmApplicationGatewayRequestRoutingRule -ApplicationGateway $AppGW -Name $httpsRuleName -RuleType basic -BackendHttpSettings $AGHTTP -HttpListener $AGHttpsListener -BackendAddressPool $AGBEP

   Set-AzureRmApplicationGateway -ApplicationGateway $AppGw
 }
 