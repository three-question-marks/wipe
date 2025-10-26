$customization_files_path = "C:\Recovery\AutoApply\CustomizationFiles"
$desktop_path = "$Home\Desktop"

Remove-Item "C:\Users\Public\Desktop\Microsoft Edge.lnk" -Force -ErrorAction Ignore

$wsh = New-Object -COMObject WScript.Shell
$shortcut = $wsh.CreateShortcut("$desktop_path\Install.lnk")
$shortcut.TargetPath = "$customization_files_path"
$shortcut.Save()

$shortcut = $wsh.CreateShortcut("$desktop_path\AnyDesk.lnk")
$shortcut.TargetPath = "$customization_files_path\AnyDesk.exe"
$shortcut.Save()
