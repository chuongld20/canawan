# install-windows-exporter.ps1
# PowerShell script to install Windows Exporter v0.30.6

# Set execution policy to allow script execution
Set-ExecutionPolicy Bypass -Scope Process -Force

# Define variables
$version = "0.30.6"
$msiUrl = "https://github.com/prometheus-community/windows_exporter/releases/download/v$version/windows_exporter-$version-amd64.msi"
$msiFile = "$env:TEMP\windows_exporter-$version-amd64.msi"

# Download the MSI installer
Write-Host "🔽 Downloading Windows Exporter v$version..."
Invoke-WebRequest -Uri $msiUrl -OutFile $msiFile

# Install Windows Exporter
Write-Host "⚙️ Installing Windows Exporter..."
Start-Process msiexec.exe -ArgumentList "/i `"$msiFile`" /quiet /norestart" -Wait

# Open firewall port 9182
Write-Host "🔓 Opening firewall port 9182..."
New-NetFirewallRule -DisplayName "Windows Exporter Port 9182" -Direction Inbound -Protocol TCP -LocalPort 9182 -Action Allow

# Start the Windows Exporter service
Write-Host "🚀 Starting windows_exporter service..."
Start-Service -Name "windows_exporter"

# Check service status
Write-Host "`n📋 Service status:"
Get-Service -Name "windows_exporter"

# Completion message
Write-Host "`n✅ Installation complete! Access metrics at: http://localhost:9182/metrics"
