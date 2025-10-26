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

function Download-File {
    param (
        [string]$Source,
        [string]$Destination,
        [switch]$Force = $false,
        [string]$DisplayName = '',
        [string]$TransferPolicy = 'Always'
    )

    $Description = 'This is a file transfer that uses the Background Intelligent Transfer Service (BITS).'
    if ($DisplayName -ne '') {
        $Description = "Downloading $DisplayName..."
    } else {
        $DisplayName = 'BITS Transfer'
    }
    $file_exists = (-Not (Test-Path -LiteralPath $Destination -PathType Leaf))
    if ($Force -or $file_exists) {
        Start-BitsTransfer -Source $Source -Destination $Destination -TransferPolicy $TransferPolicy `
            -Description $Description -DisplayName $DisplayName
    } else {
        Write-Host "$DisplayName has already been uploaded - skipping"
    }
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

Write-Host "Downloading unattend.xml..."
(New-Object System.Net.WebClient).DownloadFile($unattend_xml_source, "$autoapply_dir\unattend.xml")

Write-Host "Downloading installers..."
$source = "https://download.anydesk.com/AnyDesk.exe"
$destination = "$customization_files_path\AnyDesk.exe"
Download-File -Source $source -Destination $destination -DisplayName "AnyDesk"

$release = Invoke-RestMethod "https://api.github.com/repos/ip7z/7zip/releases/latest"
$asset = $release.assets | Where-Object {$_.Name -match '^7z[0-9]+\.exe$'}
$source = $asset.browser_download_url
$destination = "$customization_files_path\7-Zip.exe"
Download-File -Source $source -Destination $destination -DisplayName "7-Zip"

$source = "https://dl.google.com/dl/chrome/install/googlechromestandaloneenterprise64.msi"
$destination = "$customization_files_path\GoogleChromeEnterprise.msi"
Download-File -Source $source -Destination $destination -DisplayName "Google Chrome"

$choice0 = New-ChoiceDescription -Name Wipe -Description 'Wipe everything'
$choice1 = New-ChoiceDescription -Name '&Abort' -Description 'Cancel operation'
$choice = Prompt-ForChoice -Title "If you ready to wipe computer, type 'wipe'" -Default 1 -Choices $choice0,$choice1
if ($choice -eq 1) {
    throw 'Aborted'
}

$winre_drivers = Get-ChildItem -Path $winre_drivers_dir -Attributes 'H,S,!H,!S' -ErrorAction Ignore
if (($winre_drivers | Measure-Object).Count -gt 0) {
    $recovery_mount_dir = "$tmp_dir\recovery"
    $winre_mount_dir = "$tmp_dir\winre"

    Write-Host "Locating recovery partition..."
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

    Write-Host "Cleaning up working directories..."
    try {
        $null = Dismount-WindowsImage -Path $winre_mount_dir -Discard -ErrorAction Ignore
    }
    catch {}
    try {
        $null = Remove-PartitionAccessPath -AccessPath "$recovery_mount_dir" -DiskNumber "$disk_number" -PartitionNumber "$partition_number" -ErrorAction Ignore
    }
    catch {}

    Write-Host "Mounting recovery partition..."
    $null = New-Item -Path "$recovery_mount_dir" -ItemType Directory -Force
    $null = Add-PartitionAccessPath -AccessPath "$recovery_mount_dir" -DiskNumber "$disk_number" -PartitionNumber "$partition_number"

    Write-Host "Mounting WinRE image..."
    $null = New-Item -Path $winre_mount_dir -ItemType Directory -Force
    $null = Mount-WindowsImage -ImagePath $winre_image_path -Path $winre_mount_dir -Index 1
    
    Write-Host "Adding drivers to WinRE..."
    $null = Add-WindowsDriver -Path $winre_mount_dir -Driver $winre_drivers_dir -Recurse

    Write-Host "Applying changes to WinRE image..."
    $null = Dismount-WindowsImage -Path $winre_mount_dir -Save

    Write-Host "Unmounting recovery partition..."
    $null = Remove-PartitionAccessPath -AccessPath "$recovery_mount_dir" -DiskNumber "$disk_number" -PartitionNumber "$partition_number"
} else {
    Write-Host "WinRE drivers not found - skipping"
}

Write-Host "Creating scheduled task to wipe computer..."
$wipe_script | Out-File -Force -FilePath $wipe_script_path

$action = New-ScheduledTaskAction -Execute "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -Argument "-ExecutionPolicy Bypass -File ""$wipe_script_path"""
$principal = New-ScheduledTaskPrincipal -RunLevel Highest -UserId "S-1-5-18"
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -DontStopOnIdleEnd -MultipleInstances IgnoreNew
$task = New-ScheduledTask -Action $action -Principal $principal -Settings $settings
$null = Register-ScheduledTask wipe -Force -InputObject $task
Write-Host "Launching scheduled task..."
Start-ScheduledTask -TaskName wipe
