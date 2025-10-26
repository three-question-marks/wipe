$customization_files_path = "C:\Recovery\AutoApply\CustomizationFiles"

Start-Process -FilePath PnPUtil.exe -ArgumentList "/add-driver","$customization_files_path\Drivers\*.inf","/install","/subdirs" -NoNewWindow
