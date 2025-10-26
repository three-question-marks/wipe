$customization_files_path = "C:\Recovery\AutoApply\CustomizationFiles"

Start-Process -FilePath "$customization_files_path\7-Zip.exe" -ArgumentList "/S" -NoNewWindow

Start-Process -FilePath "msiexec.exe" -ArgumentList "/i","$customization_files_path\GoogleChromeEnterprise.msi","/passive","/norestart" -NoNewWindow
