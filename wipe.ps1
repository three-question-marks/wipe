$wipe_script_path = 'C:\wipe.ps1'
$wipe_script = @'
$namespaceName = "root\cimv2\mdm\dmmap"
$className = "MDM_RemoteWipe"
$methodName = "doWipeProtectedMethod"

$session = New-CimSession

$params = New-Object Microsoft.Management.Infrastructure.CimMethodParametersCollection
$param = [Microsoft.Management.Infrastructure.CimMethodParameter]::Create("param", "", "String", "In")
$params.Add($param)

$instance = Get-CimInstance -Namespace $namespaceName -ClassName $className -Filter "ParentID='./Vendor/MSFT' and InstanceID='RemoteWipe'"
$session.InvokeMethod($namespaceName, $instance, $methodName, $params)
'@
$unattend_xml_source = "https://raw.githubusercontent.com/three-question-marks/wipe/refs/heads/main/unattend.xml"

$null = New-Item -Path "C:\Recovery\AutoApply\CustomizationFiles\Drivers" -ItemType Directory -Force

(New-Object System.Net.WebClient).DownloadFile($unattend_xml_source, "C:\Recovery\AutoApply\unattend.xml")

$source = "https://download.anydesk.com/AnyDesk.exe"
Start-BitsTransfer -Source $source -Destination "C:\Recovery\AutoApply\CustomizationFiles\AnyDesk.exe" `
  -TransferPolicy "Always" -Description "Downloading Anydesk.exe..." -DisplayName "Anydesk" -ErrorAction "Continue"

$release = Invoke-RestMethod 'https://api.github.com/repos/ip7z/7zip/releases/latest'
$asset = $release.assets | Where-Object {$_.Name -match '^7z[0-9]+\.exe$'}
$source = $asset.browser_download_url
Start-BitsTransfer -Source $source -Destination "C:\Recovery\AutoApply\CustomizationFiles\7-Zip.exe" `
  -TransferPolicy "Always" -Description "Downloading 7-Zip..." -DisplayName "7-Zip" -ErrorAction "Continue"

$source = 'https://dl.google.com/chrome/install/latest/chrome_installer.exe'
Start-BitsTransfer -Source $source -Destination "C:\Recovery\AutoApply\CustomizationFiles\Google Chrome.exe" `
  -TransferPolicy "Always" -Description "Downloading Google Chrome online installer..." -DisplayName "Google Chrome" -ErrorAction "Continue"

Write-Host -NoNewLine 'Press any key to wipe...';
$null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown');

$wipe_script | Out-File -Force -FilePath $wipe_script_path

$action = New-ScheduledTaskAction -Execute "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -Argument "-ExecutionPolicy Bypass -File ""$wipe_script_path"""
$principal = New-ScheduledTaskPrincipal -RunLevel "Highest" -UserId "S-1-5-18"
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -DontStopOnIdleEnd -MultipleInstances "Queue" 
$task = New-ScheduledTask -Action $action -Principal $principal -Settings $settings
$null = Register-ScheduledTask wipe -Force -InputObject $task
Start-ScheduledTask -TaskName wipe
