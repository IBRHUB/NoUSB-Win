# Requires -RunAsAdministrator
# WPF GUI for Deploying Windows Image (ISO/ESD/WIM) with Autounattend and OEM scripts

# Prerequisite: PowerShell 5.1+
if ($PSVersionTable.PSVersion.Major -lt 5 -or ($PSVersionTable.PSVersion.Major -eq 5 -and $PSVersionTable.PSVersion.Minor -lt 1)) {
    Write-Host 'PowerShell 5.1 or higher is required.' -ForegroundColor Red
    exit 1
}

# Ensure STA for WPF
if ($host.Runspace.ApartmentState -ne 'STA') {
    powershell.exe -STA -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath @PSBoundParameters
    exit
}

# Elevate if not Administrator
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole] 'Administrator')) {
    Start-Process powershell.exe -Verb RunAs -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File',$PSCommandPath
    exit
}

# Load WPF assemblies
Add-Type -AssemblyName PresentationCore,PresentationFramework,WindowsBase,System.Xaml

# Logging helper
function Write-Log {
    param($msg)
    "$((Get-Date).ToString('o')) - $msg" | Out-File -FilePath "$env:TEMP\DeployLog.txt" -Append
}

# Status helper
function Set-Status {
    param($msg, [int]$percent)
    $status.Text = $msg
    if ($percent -ge 0) { $progress.Value = $percent }
    Write-Log $msg
}

# Define XAML UI
[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Deploy Windows Image" Height="650" Width="600"
        MinWidth="550" MinHeight="600"
        WindowStartupLocation="CenterScreen" AllowDrop="True"
        Background="{DynamicResource WindowBackground}">
  <Window.Resources>
    <!-- Colors and Brushes -->
    <SolidColorBrush x:Key="WindowBackground" Color="#0F1225"/>
    <SolidColorBrush x:Key="AccentBrush" Color="#3294FF"/>
    <SolidColorBrush x:Key="TextPrimary" Color="#E0E8F8"/>
    <SolidColorBrush x:Key="TextSecondary" Color="#A0B0D0"/>
    <Thickness x:Key="DefaultMargin">8</Thickness>
    <Style TargetType="Button">
      <Setter Property="Foreground" Value="White"/>
      <Setter Property="Background" Value="{DynamicResource AccentBrush}"/>
      <Setter Property="Padding" Value="6,2"/>
      <Setter Property="Margin" Value="{StaticResource DefaultMargin}"/>
      <Setter Property="FontWeight" Value="Bold"/>
      <Setter Property="Cursor" Value="Hand"/>
    </Style>
  </Window.Resources>
  <Grid Margin="16">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>   <!-- Header -->
      <RowDefinition Height="Auto"/>   <!-- Steps -->
      <RowDefinition Height="*"/>      <!-- Editions -->
      <RowDefinition Height="Auto"/>   <!-- Progress -->
    </Grid.RowDefinitions>
    <!-- Header -->
    <StackPanel Grid.Row="0" Margin="0,0,0,20">
      <TextBlock Text="Optimized Windows." Foreground="{DynamicResource TextPrimary}" FontSize="32" FontWeight="Bold"/>
      <TextBlock Text="Designed for Enthusiasts." Foreground="{DynamicResource AccentBrush}" FontSize="28" FontWeight="SemiBold"/>
      <TextBlock Text="Lean, privacy-focused, and high-performance deployment tool." Foreground="{DynamicResource TextSecondary}" FontSize="14" Margin="0,4,0,0"/>
    </StackPanel>
    <!-- Steps Grid -->
    <Grid Grid.Row="1" Margin="0,0,0,20">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="2*"/>
        <ColumnDefinition Width="1*"/>
      </Grid.ColumnDefinitions>
      <Grid.RowDefinitions>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
      </Grid.RowDefinitions>
      <!-- Image -->
      <TextBlock Grid.Row="0" Grid.Column="0" Text="1. Select Image File" Foreground="{DynamicResource TextPrimary}" FontWeight="SemiBold"/>
      <StackPanel Grid.Row="0" Grid.Column="1" Orientation="Horizontal">
        <TextBox x:Name="txtImage" Width="300" IsReadOnly="True" Foreground="{DynamicResource TextPrimary}" Background="#1C2238"/>
        <Button x:Name="btnBrowseImage" Content="Browse…"/>
      </StackPanel>
      <!-- Drive -->
      <TextBlock Grid.Row="1" Grid.Column="0" Text="2. Choose Target Drive" Foreground="{DynamicResource TextPrimary}" FontWeight="SemiBold"/>
      <StackPanel Grid.Row="1" Grid.Column="1" Orientation="Horizontal">
        <ComboBox x:Name="cboVolumes" Width="120"/>
        <TextBlock x:Name="txtFree" Foreground="{DynamicResource TextSecondary}" VerticalAlignment="Center" Margin="8,0,0,0"/>
      </StackPanel>
      <!-- Unattend -->
      <TextBlock Grid.Row="2" Grid.Column="0" Text="3. (Optional) Autounattend XML" Foreground="{DynamicResource TextPrimary}" FontWeight="SemiBold"/>
      <StackPanel Grid.Row="2" Grid.Column="1" Orientation="Horizontal">
        <TextBox x:Name="txtUnattend" Width="300" IsReadOnly="True" Foreground="{DynamicResource TextPrimary}" Background="#1C2238"/>
        <Button x:Name="btnBrowseUnattend" Content="Browse…"/>
      </StackPanel>
      <!-- Load Editions Button spans both columns -->
      <Button Grid.Row="3" Grid.Column="1" x:Name="btnLoadEditions" Content="Load Editions" HorizontalAlignment="Right"/>
    </Grid>
    <!-- Editions List -->
    <Border Grid.Row="2" Background="#1C2238" CornerRadius="6" Padding="8">
      <ScrollViewer VerticalScrollBarVisibility="Auto">
        <ListBox x:Name="lstEditions" Foreground="{DynamicResource TextPrimary}" Background="Transparent" BorderThickness="0"/>
      </ScrollViewer>
    </Border>
    <!-- Apply & Progress -->
    <StackPanel Grid.Row="3" Orientation="Vertical" Margin="0,20,0,0">
      <Button x:Name="btnApply" Content="Apply Image Now" HorizontalAlignment="Center" Width="200"/>
      <ProgressBar x:Name="progress" Height="16" Minimum="0" Maximum="100" Margin="0,8,0,0"/>
      <TextBlock x:Name="status" Text="Ready" Foreground="{DynamicResource TextSecondary}" HorizontalAlignment="Center" Margin="0,4,0,0"/>
    </StackPanel>
  </Grid>
</Window>
"@

# Load and instantiate UI
$reader = New-Object System.Xml.XmlNodeReader($xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)

# Retrieve controls
$btnBrowseImage    = $window.FindName('btnBrowseImage')
$txtImage          = $window.FindName('txtImage')
$cboVolumes        = $window.FindName('cboVolumes')
$txtFree           = $window.FindName('txtFree')
$btnBrowseUnattend = $window.FindName('btnBrowseUnattend')
$txtUnattend       = $window.FindName('txtUnattend')
$btnLoadEditions   = $window.FindName('btnLoadEditions')
$lstEditions       = $window.FindName('lstEditions')
$btnApply          = $window.FindName('btnApply')
$progress          = $window.FindName('progress')
$status            = $window.FindName('status')

# State variables
[string]$imagePath    = ''
[string]$wimPath      = ''
[string]$unattendPath = ''
[string]$mountDrive   = ''
[string]$targetDrive  = ''
[int]   $editionIndex = 0

# Populate drives
function Update-Volumes {
    $cboVolumes.Items.Clear()
    Get-Volume | Where-Object FileSystem -EQ 'NTFS' | ForEach-Object {
        [void]$cboVolumes.Items.Add($_.DriveLetter + ':')
    }
    if ($cboVolumes.Items.Count -gt 0) {
        $cboVolumes.SelectedIndex = 0
        Update-FreeSpace
    }
}

function Update-FreeSpace {
    if ($cboVolumes.SelectedItem) {
        $drvInfo = [IO.DriveInfo]::new($cboVolumes.SelectedItem)
        $txtFree.Text = "Free: $([math]::Round($drvInfo.AvailableFreeSpace/1GB,1)) GB"
    }
}

Update-Volumes
$cboVolumes.Add_SelectionChanged({ Update-FreeSpace })

# Disable/Enable UI
function Set-Busy {
    param([bool]$busy)
    foreach ($ctrl in @($btnBrowseImage, $btnBrowseUnattend, $btnLoadEditions, $btnApply)) {
        $ctrl.IsEnabled = -not $busy
    }
}

# Drag & Drop support
$window.Add_Drop({ param($s,$e)
    $e.Effects = 'Copy'
    $files = $e.Data.GetData('FileDrop')
    foreach ($f in $files) {
        switch ([IO.Path]::GetExtension($f).ToLower()) {
            '.iso' { $imagePath = $f; $txtImage.Text = $f; $btnLoadEditions.IsEnabled = $true }
            '.wim' { $imagePath = $f; $txtImage.Text = $f; $wimPath = $f; $btnLoadEditions.IsEnabled = $true }
            '.esd' { $imagePath = $f; $txtImage.Text = $f; $wimPath = $f; $btnLoadEditions.IsEnabled = $true }
            '.xml' { $unattendPath = $f; $txtUnattend.Text = [IO.Path]::GetFileName($f) }
        }
    }
})

# Browse Image button
$btnBrowseImage.Add_Click({
    $dlg = New-Object Microsoft.Win32.OpenFileDialog
    $dlg.Filter = 'Image Files (*.iso;*.wim;*.esd)|*.iso;*.wim;*.esd'
    $dlg.InitialDirectory = Join-Path $env:USERPROFILE 'Downloads'
    if ($dlg.ShowDialog() -eq $true) {
        $imagePath = $dlg.FileName
        $txtImage.Text = $imagePath
        $btnLoadEditions.IsEnabled = $true
    }
})

# Browse Unattend XML button
$btnBrowseUnattend.Add_Click({
    $dlg = New-Object Microsoft.Win32.OpenFileDialog
    $dlg.Filter = 'XML Files (*.xml)|*.xml'
    $dlg.InitialDirectory = Join-Path $env:USERPROFILE 'Desktop'
    if ($dlg.ShowDialog() -eq $true) {
        $unattendPath = $dlg.FileName
        $txtUnattend.Text = [IO.Path]::GetFileName($unattendPath)
    }
})

# Load Editions button
$btnLoadEditions.Add_Click({
    Set-Busy $true; Set-Status 'Loading editions...' 10
    try {
        if ([IO.Path]::GetExtension($imagePath).ToLower() -eq '.iso') {
            Set-Status 'Mounting ISO...' 20
            Mount-DiskImage -ImagePath $imagePath -ErrorAction Stop | Out-Null
            $vol = Get-DiskImage -ImagePath $imagePath | Get-Volume
            $mountDrive = $vol.DriveLetter + ':'
            $src = Join-Path $mountDrive 'sources'
            if (Test-Path (Join-Path $src 'install.esd')) {
                $wimPath = Join-Path $src 'install.esd'
            } else {
                $wimPath = Join-Path $src 'install.wim'
            }
        } else {
            $wimPath = $imagePath
            $mountDrive = ''
        }
        $lstEditions.Items.Clear()
        Set-Status 'Retrieving editions...' 40
        Get-WindowsImage -ImagePath $wimPath | ForEach-Object {
            [void]$lstEditions.Items.Add("$($_.ImageIndex): $($_.ImageName)")
        }
        $lstEditions.SelectedIndex = 0
        $btnApply.IsEnabled = $true
        Set-Status 'Editions loaded' 60
    } catch {
        Write-Log $_.Exception.Message
        [System.Windows.MessageBox]::Show($_.Exception.Message, 'Error', [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
    } finally {
        Set-Busy $false; Set-Status 'Ready' 0
    }
})

# Apply button with user-error guards
$btnApply.Add_Click({
    Set-Busy $true; Set-Status 'Checking selection...' 50
    try {
        $osDrive = $env:SystemDrive
        $targetDrive = $cboVolumes.SelectedItem
        if ($targetDrive -eq $osDrive) {
            [System.Windows.MessageBox]::Show('Cannot deploy to the system drive.', 'Error', [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
            return
        }
        if (-not $lstEditions.SelectedItem) {
            [System.Windows.MessageBox]::Show('Please select an edition first.', 'Error', [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
            return
        }
        if ($unattendPath) {
            try { [xml](Get-Content $unattendPath) | Out-Null } catch {
                [System.Windows.MessageBox]::Show('Invalid Unattend XML file.', 'Error', [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
                return
            }
        }
        $today = (Get-Date).Date
        $rootPath = Join-Path $targetDrive ''
        $oldDirs = Get-ChildItem -Path $rootPath -Directory -Recurse -ErrorAction SilentlyContinue |
                   Where-Object { $_.LastWriteTime.Date -lt $today }
        if ($oldDirs) {
            $list = ($oldDirs | Select-Object -First 5 -ExpandProperty FullName) -join "`n"
            [System.Windows.MessageBox]::Show("Found folders older than today:`n$list", 'Error', [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
            return
        }
        Set-Status 'Verifying space requirements...' 70
        $minRequired = 64GB
        if ($drvInfo.AvailableFreeSpace -lt $minRequired) {
            [System.Windows.MessageBox]::Show("Insufficient free space. At least 64 GB is required.", 'Error', [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
            return
        }
        $imageSize = (Get-Item $wimPath).Length
        if ($drvInfo.AvailableFreeSpace -lt ($imageSize * 1.1)) {
            [System.Windows.MessageBox]::Show('Insufficient space.', 'Error', [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
            return
        }
        if ([System.Windows.MessageBox]::Show("Deploy edition $($lstEditions.SelectedItem) to $targetDrive?", 'Confirm', [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Question) -ne 'Yes') {
            return
        }
        Set-Status 'Applying image...' 80
        Write-Log 'Deploying'
        $editionIndex = [int]($lstEditions.SelectedItem -split ':')[0]
        Expand-WindowsImage -ImagePath $wimPath -ApplyPath "$targetDrive\" -Index $editionIndex -ErrorAction Stop
        if ($unattendPath) {
            Use-WindowsUnattend -Path "$targetDrive\" -UnattendPath $unattendPath
            Copy-Item $unattendPath -Destination (Join-Path $targetDrive 'autounattend.xml') -Force
        }
        if ($mountDrive) {
            $oemScripts = Join-Path $mountDrive 'sources\$OEM$\$\Setup\Scripts\*'
            if (Test-Path $oemScripts) {
                Copy-Item $oemScripts -Destination (Join-Path $targetDrive 'Windows\Setup\Scripts') -Recurse -Force
            }
        }
        bcdboot "$targetDrive\Windows" | Out-Null
        Set-Status 'Done' 100
        Write-Log 'Success'
        if ([System.Windows.MessageBox]::Show('Reboot now?', 'Finished', [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Question) -eq 'Yes') {
            Restart-Computer
        }
    } catch {
        Write-Log $_.Exception.Message
        [System.Windows.MessageBox]::Show($_.Exception.Message, 'Error', [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
    } finally {
        if ($mountDrive) {
            Dismount-DiskImage -ImagePath $imagePath -ErrorAction SilentlyContinue | Out-Null
        }
        Set-Busy $false
    }
})

# Prevent default drag-over effect
$window.Add_PreviewDragOver({ $args.Handled = $true })

# Show window
$window.ShowDialog() | Out-Null
