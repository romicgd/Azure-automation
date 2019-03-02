function Add-CertificatesToKeyVaultSecrets {
 <#
.SYNOPSIS
    Adds pfx content, pfx password and cert to Azure KeyVault secrets to be used for Azure applications, App Gateways etc..
    This is useful for Azure services that not yet support integration with KeyValut certificates. 

.EXAMPLE
#>
Param (
[Parameter(Mandatory=$true)]
[string]$keyVaultName,
[Parameter(Mandatory=$true)]
[string]$certificateName,
[Parameter(Mandatory=$true)]
[string]$pfxFilePath,
[Parameter(Mandatory=$true)]
[string]$pfxPassword,
[Parameter(Mandatory=$true)]
[string]$certificatePath
)
    Add-PfxToKeyVaultSecrets -keyVaultName $keyVaultName -certificateName $certificateName -pfxFilePath $pfxFilePath  -pfxPassword $pfxPassword
    Add-PublicCertificateToKeyVaultSecrets -keyVaultName $keyVaultName -certificateName $certificateName -cerFilePath $certificatePath
}


function Add-PfxToKeyVaultSecrets {
    <#
   .SYNOPSIS
       Adds pfx content, pfx password to Azure KeyVault secrets to be used for Azure applications, App Gateways etc..
       This is useful for Azure services that not yet support integration with KeyValut certificates. 
   
   .EXAMPLE
   #>
   Param (
   [Parameter(Mandatory=$true)]
   [string]$keyVaultName,
   [Parameter(Mandatory=$true)]
   [string]$certificateName,
   [Parameter(Mandatory=$true)]
   [string]$pfxFilePath,
   [Parameter(Mandatory=$true)]
   [string]$pfxPassword
   )
       $pfxsecretname="sslCertificateData-$certificateName"
       $pfxPasswordSecretname="sslCertificatePassword-$certificateName"
       $flag = [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::Exportable
       $collection = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2Collection 
       $collection.Import($pfxFilePath, $pfxPassword, $flag)
       $pkcs12ContentType = [System.Security.Cryptography.X509Certificates.X509ContentType]::Pkcs12
       $clearBytes = $collection.Export($pkcs12ContentType, $pfxPassword)
       $fileContentEncoded = [System.Convert]::ToBase64String($clearBytes)
       $secret = ConvertTo-SecureString -String $fileContentEncoded -AsPlainText -Force
       $secretContentType = 'application/x-pkcs12'
       # set pfx data secret
       Set-AzureKeyVaultSecret -VaultName $keyVaultName -Name $pfxsecretname -SecretValue $Secret -ContentType $secretContentType
       # set pfx password secret
       $passwordSecret = ConvertTo-SecureString -String $pfxPassword -AsPlainText -Force
       Set-AzureKeyVaultSecret -VaultName $keyVaultName -Name $pfxPasswordSecretname -SecretValue $passwordSecret -ContentType 'txt'
    }

function Add-PublicCertificateToKeyVaultSecrets {
    <#
   .SYNOPSIS
       Adds Public certificate to Azure KeyVault secrets to be used for Azure applications, App Gateways etc..
       This is useful for Azure services that not yet support integration with KeyValut certificates. 
   
   .EXAMPLE
   #>
   Param (
   [Parameter(Mandatory=$true)]
   [string]$keyVaultName,
   [Parameter(Mandatory=$true)]
   [string]$certificateName,
   [Parameter(Mandatory=$true)]
   [string]$cerFilePath
   )
    $publicCertSecretName="backendPublicKeyData-$certificateName"
    $certContentEncoded = Get-content $cerFilePath -Raw
    $secret = ConvertTo-SecureString -String $certContentEncoded -AsPlainText -Force
    $secretContentType = 'txt'
    Set-AzureKeyVaultSecret -VaultName $keyVaultName -Name $publicCertSecretName -SecretValue $Secret -ContentType $secretContentType
}
