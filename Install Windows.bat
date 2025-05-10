<# : Installation.bat
@echo off
setlocal enabledelayedexpansion
color 0A
cd /d "%~dp0"
title Windows ISO Direct Installer v1.0

:: ================= INITIALIZATION =================
:: Check for Admin privileges
echo Checking for administrative privileges...
net session >nul 2>&1
if %errorlevel% neq 0 (
    color 0C
    echo ERROR: This script requires administrative privileges.
    echo Please right-click and select "Run as administrator".
    pause
    exit /b 1
)

:: Check for 7zip
if not exist 7z.exe (
    color 0C
    echo ERROR: 7Zip executable (7z.exe) not found in the current directory.
    echo Please download this repository as a .zip and extract all files.
    pause
    exit /b 1
)

:: Check for DISM availability
dism /? >nul 2>&1
if %errorlevel% neq 0 (
    color 0C
    echo ERROR: Windows Deployment Image Servicing and Management (DISM) not found.
    echo This tool requires Windows 8 or later.
    pause
    exit /b 1
)

:: Setup temporary directory
set "TEMP_DIR=C:\WindowsInstallation"
if exist "%TEMP_DIR%" (
    choice /C YN /M "A previous installation was found. Clear it and continue?"
    if errorlevel 2 exit /b 0
    if errorlevel 1 (
        echo Cleaning up previous installation files...
        rd /s /q "%TEMP_DIR%" >nul 2>&1
    )
)

:: Create temporary directory
mkdir "%TEMP_DIR%" 2>nul

:: ================= MAIN MENU =================
:MainMenu
cls
echo ================================================
echo =           WINDOWS ISO DIRECT INSTALLER       =
echo =                                              =
echo =  Install Windows directly without USB drive  =
echo ================================================
echo.
echo [1] Start installation (with ISO selection)
echo [2] Advanced installation (with XML customization)
echo [3] View system information
echo [4] Help and information
echo [5] Exit
echo.
set /p choice=Enter your choice (1-5): 

if "%choice%"=="1" goto StandardInstall
if "%choice%"=="2" goto AdvancedInstall
if "%choice%"=="3" goto SystemInfo
if "%choice%"=="4" goto HelpInfo
if "%choice%"=="5" exit /b 0
goto MainMenu

:: ================= SYSTEM INFORMATION =================
:SystemInfo
cls
echo ================================================
echo =            SYSTEM INFORMATION               =
echo ================================================
echo.
echo Operating System:
ver
echo.
echo Available Disk Drives:
wmic logicaldisk get deviceid, volumename, description, filesystem, size, freespace
echo.
echo CPU Information:
wmic cpu get name, numberofcores, maxclockspeed
echo.
echo RAM Information:
wmic computersystem get totalphysicalmemory
wmic os get freephysicalmemory
echo.
pause
goto MainMenu

:: ================= HELP INFORMATION =================
:HelpInfo
cls
echo ================================================
echo =            HELP AND INFORMATION             =
echo ================================================
echo.
echo This tool allows you to install Windows directly from an ISO file
echo without requiring a USB drive or DVD. It works by extracting the
echo ISO contents and using DISM to apply the Windows image to a
echo selected partition.
echo.
echo REQUIREMENTS:
echo  - Administrative privileges
echo  - 7zip (7z.exe) in the same directory as this script
echo  - A target partition formatted and ready (NOT the active Windows partition)
echo  - At least 10GB free space on the C: drive for temporary files
echo.
echo INSTRUCTIONS:
echo  1. Create and format a partition for the new Windows installation
echo  2. Run this script and select your preferred installation method
echo  3. Select the Windows ISO file to use
echo  4. Optionally select an autounattend.xml file for unattended installation
echo  5. Choose the target drive letter
echo  6. Wait for installation to complete
echo  7. Reboot to access your new Windows installation
echo.
pause
goto MainMenu

:: ================= STANDARD INSTALLATION =================
:StandardInstall
cls
echo ================================================
echo =            STANDARD INSTALLATION            =
echo ================================================

:: Choose ISO file
echo.
echo Choose the Windows ISO file to install:
for /f "delims=" %%I in ('powershell -noprofile "iex (${%~f0} | out-string)"') do (
    set "ISO_FILE=%%~I"
)

if not defined ISO_FILE (
    echo No ISO file selected. Returning to main menu.
    timeout /t 3 >nul
    goto MainMenu
)

echo.
echo Selected ISO: !ISO_FILE!
echo.
echo Extracting ISO contents to %TEMP_DIR% (this may take several minutes)...
echo.

:: Show progress indicator
start /b cmd /c "for /l %%i in (1,1,100) do (echo %%i ^> %TEMP_DIR%\progress.txt & timeout /t 1 /nobreak >nul)"
7z.exe x -y -o"%TEMP_DIR%" "!ISO_FILE!" >nul

:: Kill the progress indicator
taskkill /f /im timeout.exe >nul 2>&1

goto SelectDrive

:: ================= ADVANCED INSTALLATION =================
:AdvancedInstall
cls
echo ================================================
echo =           ADVANCED INSTALLATION             =
echo ================================================

:: Choose ISO file
echo.
echo Choose the Windows ISO file to install:
for /f "delims=" %%I in ('powershell -noprofile "iex (${%~f0} | out-string)"') do (
    set "ISO_FILE=%%~I"
)

if not defined ISO_FILE (
    echo No ISO file selected. Returning to main menu.
    timeout /t 3 >nul
    goto MainMenu
)

echo.
echo Selected ISO: !ISO_FILE!
echo.

:: Choose autounattend.xml file
echo Choose the autounattend.xml file for customized installation:
for /f "delims=" %%X in ('powershell -noprofile "iex (${%~f1} | out-string)"') do (
    set "XML_FILE=%%~X"
)

if not defined XML_FILE (
    echo No autounattend.xml selected. Continuing with standard installation.
    set "XML_MODE=STANDARD"
) else (
    echo Selected XML: !XML_FILE!
    echo Copying customization file...
    copy /Y "!XML_FILE!" "%TEMP_DIR%\autounattend.xml" >nul
    set "XML_MODE=CUSTOM"
)

echo.
echo Extracting ISO contents to %TEMP_DIR% (this may take several minutes)...
echo.

:: Show progress indicator
start /b cmd /c "for /l %%i in (1,1,100) do (echo %%i ^> %TEMP_DIR%\progress.txt & timeout /t 1 /nobreak >nul)"
7z.exe x -y -o"%TEMP_DIR%" "!ISO_FILE!" >nul

:: Kill the progress indicator
taskkill /f /im timeout.exe >nul 2>&1

goto SelectDrive

:: ================= SELECT TARGET DRIVE =================
:SelectDrive
cls
echo ================================================
echo =           SELECT TARGET DRIVE               =
echo ================================================
echo.
echo Available drives:
echo.
wmic logicaldisk get deviceid, volumename, description, filesystem, size, freespace
echo.
echo WARNING: DO NOT select your current Windows drive (usually C:)
echo          The target drive will be overwritten with a new Windows installation.
echo.
:DrivePrompt
set /p "TARGET_DRIVE=Enter the target drive letter (e.g., D): "

:: Validate drive input
set "TARGET_DRIVE=%TARGET_DRIVE%:"
if not exist "%TARGET_DRIVE%\" (
    echo ERROR: Drive %TARGET_DRIVE% does not exist. Please try again.
    goto DrivePrompt
)

:: Confirm if it's not C:
if /i "%TARGET_DRIVE%"=="C:" (
    echo.
    echo WARNING: You have selected your system drive (C:).
    echo This will likely fail and may damage your current Windows installation.
    echo.
    choice /C YN /M "Are you absolutely sure you want to continue?"
    if errorlevel 2 goto DrivePrompt
)

echo.
echo Installing Windows to drive %TARGET_DRIVE%
echo This process may take 15-30 minutes depending on your system.
echo.
choice /C YN /M "Ready to begin installation?"
if errorlevel 2 goto MainMenu

:: ================= APPLY WINDOWS IMAGE =================
:ApplyImage
cls
echo ================================================
echo =           INSTALLING WINDOWS                =
echo =                                              =
echo =          Please wait patiently...           =
echo ================================================
echo.

:: Determine which image file exists
set "WIM_FILE="
set "ESD_FILE="

if exist "%TEMP_DIR%\sources\install.wim" set "WIM_FILE=%TEMP_DIR%\sources\install.wim"
if exist "%TEMP_DIR%\sources\install.esd" set "ESD_FILE=%TEMP_DIR%\sources\install.esd"

if not defined WIM_FILE if not defined ESD_FILE (
    color 0C
    echo ERROR: No Windows image file found in the ISO.
    echo The ISO file may be corrupted or is not a valid Windows installation media.
    pause
    goto Cleanup
)

:: Get available image indexes and editions
if defined WIM_FILE (
    echo Available Windows editions in this ISO:
    dism /Get-ImageInfo /ImageFile:"%WIM_FILE%"
) else (
    echo Available Windows editions in this ISO:
    dism /Get-ImageInfo /ImageFile:"%ESD_FILE%"
)

echo.
set /p "IMAGE_INDEX=Enter the index number of the edition to install (default: 1): "
if not defined IMAGE_INDEX set "IMAGE_INDEX=1"

echo.
echo Installing Windows (Index: %IMAGE_INDEX%) to drive %TARGET_DRIVE%...

:: Apply the image based on available files and XML mode
if "%XML_MODE%"=="CUSTOM" (
    if defined WIM_FILE (
        dism /Apply-Image /ImageFile:"%WIM_FILE%" /Apply-Unattend:"%TEMP_DIR%\autounattend.xml" /Index:%IMAGE_INDEX% /ApplyDir:%TARGET_DRIVE%\
    ) else (
        dism /Apply-Image /ImageFile:"%ESD_FILE%" /Apply-Unattend:"%TEMP_DIR%\autounattend.xml" /Index:%IMAGE_INDEX% /ApplyDir:%TARGET_DRIVE%\
    )
) else (
    if defined WIM_FILE (
        dism /Apply-Image /ImageFile:"%WIM_FILE%" /Index:%IMAGE_INDEX% /ApplyDir:%TARGET_DRIVE%\
    ) else (
        dism /Apply-Image /ImageFile:"%ESD_FILE%" /Index:%IMAGE_INDEX% /ApplyDir:%TARGET_DRIVE%\
    )
)

if %ERRORLEVEL% neq 0 (
    color 0C
    echo.
    echo ERROR: Windows installation failed.
    echo Please check the error message above.
    pause
    goto Cleanup
)

:: ================= FINALIZE INSTALLATION =================
:Finalize
echo.
echo Finalizing installation...

:: Move any OEM scripts if they exist
if exist "%TEMP_DIR%\sources\$OEM$\$$\Setup\Scripts" (
    mkdir "%TARGET_DRIVE%\Windows\Setup\Scripts" 2>nul
    xcopy "%TEMP_DIR%\sources\$OEM$\$$\Setup\Scripts\*.*" "%TARGET_DRIVE%\Windows\Setup\Scripts\" /E /H /C /I /Y >nul
    echo OEM scripts copied successfully.
)

:: Move XML file for Sysprep if it exists
if exist "%TEMP_DIR%\autounattend.xml" (
    mkdir "%TARGET_DRIVE%\Windows\System32\Sysprep" 2>nul
    copy /Y "%TEMP_DIR%\autounattend.xml" "%TARGET_DRIVE%\Windows\System32\Sysprep\unattend.xml" >nul
    echo XML configuration copied successfully.
)

:: Configure boot files
echo Setting up boot configuration...
bcdboot %TARGET_DRIVE%\Windows

if %ERRORLEVEL% neq 0 (
    color 0C
    echo.
    echo ERROR: Boot configuration failed.
    echo You may need to manually configure the boot entry.
    pause
    goto Cleanup
)

:: ================= CLEANUP =================
:Cleanup
echo.
echo Cleaning up temporary files...
choice /C YN /M "Do you want to remove temporary installation files to free up space?"
if errorlevel 1 (
    rd /s /q "%TEMP_DIR%" >nul 2>&1
    if exist "%TEMP_DIR%" echo Warning: Could not completely remove temporary files.
)

:: ================= COMPLETION =================
:Complete
cls
color 0A
echo ================================================
echo =          INSTALLATION COMPLETE!              =
echo ================================================
echo.
echo Windows has been successfully installed to drive %TARGET_DRIVE%
echo.
echo Next steps:
echo  1. Restart your computer
echo  2. Select the new Windows installation from the boot menu
echo     (You may need to change boot priority in BIOS/UEFI)
echo  3. Complete the Windows setup process
echo.
echo Thank you for using the Windows ISO Direct Installer!
echo.
pause
exit /b 0

goto :EOF
: end Batch portion / begin PowerShell hybrid chimera #>
Add-Type -AssemblyName System.Windows.Forms
$f = new-object Windows.Forms.OpenFileDialog
$f.InitialDirectory = [Environment]::GetFolderPath('Desktop')
$f.Filter = "Windows ISO Files (*.iso)|*.iso|All Files (*.*)|*.*"
$f.Title = "Select Windows ISO File"
$f.Multiselect = $false
[void]$f.ShowDialog()
$f.FileName

<#
:f1
Add-Type -AssemblyName System.Windows.Forms
$x = new-object Windows.Forms.OpenFileDialog
$x.InitialDirectory = [Environment]::GetFolderPath('Desktop')
$x.Filter = "XML Files (*.xml)|*.xml|All Files (*.*)|*.*"
$x.Multiselect = $false
$x.Title = "Select autounattend.xml file (optional - press Cancel to skip)"
[void]$x.ShowDialog()
$x.FileName
#>