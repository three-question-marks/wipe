$ErrorActionPreference = "Stop"

function New-ChoiceDescription {
    param (
        [string]$Name,
        [string]$Description = ''
    )

    return [System.Management.Automation.Host.ChoiceDescription]::new($Name, $Description)
}

function Prompt-ForChoice {
    param (
        [string]$Title,
        [string]$Prompt = 'Enter your choice:',
        [System.Management.Automation.Host.ChoiceDescription[]]$Choices,
        [int]$Default = 0
    )

    $choice = $host.UI.PromptForChoice($Title, $Prompt, $Choices, $Default)
    return $choice
}

$autoapply_dir = "C:\Recovery\AutoApply"
$customization_files_path = "$autoapply_dir\CustomizationFiles"
$tmp_dir = "C:\Recovery\tmp"
$wipe_script_path = "$tmp_dir\wipe.ps1"
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
$winre_drivers_dir = "$customization_files_path\WinREDrivers"

$null = New-Item -Path $tmp_dir -ItemType Directory -Force
$null = New-Item -Path $winre_drivers_dir -ItemType Directory -Force
$null = New-Item -Path "$customization_files_path\Drivers" -ItemType Directory -Force

Write-Information "Downloading unattend.xml..."
(New-Object System.Net.WebClient).DownloadFile($unattend_xml_source, "$autoapply_dir\unattend.xml")

Write-Information "Downloading installers..."
$source = "https://download.anydesk.com/AnyDesk.exe"
Start-BitsTransfer -Source $source -Destination "$customization_files_path\AnyDesk.exe" `
  -TransferPolicy "Always" -Description "Downloading Anydesk.exe..." -DisplayName "Anydesk" -ErrorAction "Continue"

$release = Invoke-RestMethod "https://api.github.com/repos/ip7z/7zip/releases/latest"
$asset = $release.assets | Where-Object {$_.Name -match '^7z[0-9]+\.exe$'}
$source = $asset.browser_download_url
Start-BitsTransfer -Source $source -Destination "$customization_files_path\7-Zip.exe" `
  -TransferPolicy "Always" -Description "Downloading 7-Zip..." -DisplayName "7-Zip" -ErrorAction "Continue"

$source = "https://dl.google.com/chrome/install/latest/chrome_installer.exe"
Start-BitsTransfer -Source $source -Destination "$customization_files_path\Google Chrome.exe" `
  -TransferPolicy "Always" -Description "Downloading Google Chrome online installer..." -DisplayName "Google Chrome" -ErrorAction "Continue"

$choice0 = New-ChoiceDescription -Name Wipe -Description 'Wipe everything'
$choice1 = New-ChoiceDescription -Name '&Abort' -Description 'Cancel operation'
$choice = Prompt-ForChoice -Title "If you sure you want to wipe computer, type 'wipe'" -Default 1 -Choices $choice0,$choice1
if ($choice -eq 1) {
    throw 'Aborted'
}

$winre_drivers = Get-ChildItem -Path $winre_drivers_dir -Attributes 'H,S,!H,!S' -ErrorAction Ignore
if (($winre_drivers | Measure-Object).Count -gt 0) {
    $recovery_mount_dir = "$tmp_dir\recovery"
    $winre_mount_dir = "$tmp_dir\winre"

    Write-Information "Locating recovery partition..."
    $reagentc_info = reagentc /info
    if ($reagentc_info -match '.+:\s*Enabled') {
        $matches = ($reagentc_info | Select-String '.+:\s*\\\\\?\\GLOBALROOT\\device\\harddisk(\d+)\\partition(\d+)(.*)').Matches.Groups
        $disk_number = $matches[1]
        $partition_number = $matches[2]
        $winre_image_dir = $matches[3]
        $winre_image_path = "$recovery_mount_dir$winre_image_dir\Winre.wim"
    } else {
        throw 'Windows RE is disabled!'
    }

    Write-Information "Cleaning up working directories..."
    try {
        $null = Dismount-WindowsImage -Path $winre_mount_dir -Discard -ErrorAction Ignore
    }
    catch {}
    try {
        $null = Remove-PartitionAccessPath -AccessPath "$recovery_mount_dir" -DiskNumber "$disk_number" -PartitionNumber "$partition_number" -ErrorAction Ignore
    }
    catch {}

    Write-Information "Mounting recovery partition..."
    $null = New-Item -Path "$recovery_mount_dir" -ItemType Directory -Force
    $null = Add-PartitionAccessPath -AccessPath "$recovery_mount_dir" -DiskNumber "$disk_number" -PartitionNumber "$partition_number"

    Write-Information "Mounting WinRE image..."
    $null = New-Item -Path $winre_mount_dir -ItemType Directory -Force
    $null = Mount-WindowsImage -ImagePath $winre_image_path -Path $winre_mount_dir -Index 1
    
    Write-Information "Adding drivers to WinRE..."
    $null = Add-WindowsDriver -Path $winre_mount_dir -Driver $winre_drivers_dir -Recurse

    Write-Information "Applying changes to WinRE image..."
    $null = Dismount-WindowsImage -Path $winre_mount_dir -Save

    Write-Information "Unmounting recovery partition..."
    $null = Remove-PartitionAccessPath -AccessPath "$recovery_mount_dir" -DiskNumber "$disk_number" -PartitionNumber "$partition_number"
} else {
    Write-Information "WinRE drivers not found - skipping"
}

Write-Information "Creating scheduled task to wipe computer..."
$wipe_script | Out-File -Force -FilePath $wipe_script_path

$action = New-ScheduledTaskAction -Execute "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -Argument "-ExecutionPolicy Bypass -File ""$wipe_script_path"""
$principal = New-ScheduledTaskPrincipal -RunLevel "Highest" -UserId "S-1-5-18"
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -DontStopOnIdleEnd -MultipleInstances "Queue" 
$task = New-ScheduledTask -Action $action -Principal $principal -Settings $settings
$null = Register-ScheduledTask wipe -Force -InputObject $task
Write-Information "Launching scheduled task..."
Start-ScheduledTask -TaskName wipe
