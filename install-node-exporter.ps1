# -------------------------------
# install-node-exporter.ps1
# Auto install Node Exporter on Windows Server
# -------------------------------

# Variables
$NodeExporterVersion = "1.6.1"
$NodeExporterZip = "node_exporter-$NodeExporterVersion.windows-amd64.zip"
$NodeExporterUrl = "https://github.com/prometheus/node_exporter/releases/download/v$NodeExporterVersion/$NodeExporterZip"
$InstallDir = "C:\node_exporter"
$ServiceName = "NodeExporter"

$NssmUrl = "https://nssm.cc/release/nssm-2.24.zip"
$NssmZip = "$env:TEMP\nssm.zip"
$NssmExtract = "$env:TEMP\nssm"

# Step 1: Create Install Directory
if (!(Test-Path -Path $InstallDir)) {
    Write-Host "Creating install directory at $InstallDir" -ForegroundColor Cyan
    New-Item -ItemType Directory -Path $InstallDir
}

# Step 2: Download Node Exporter
Write-Host "Downloading Node Exporter..." -ForegroundColor Cyan
Invoke-WebRequest -Uri $NodeExporterUrl -OutFile "$env:TEMP\$NodeExporterZip"

# Step 3: Extract Node Exporter
Write-Host "Extracting Node Exporter..." -ForegroundColor Cyan
Expand-Archive -Path "$env:TEMP\$NodeExporterZip" -DestinationPath "$InstallDir" -Force

# Step 4: Move the executable
Move-Item -Path "$InstallDir\node_exporter-$NodeExporterVersion.windows-amd64\node_exporter.exe" -Destination "$InstallDir\node_exporter.exe" -Force
Remove-Item -Recurse -Force "$InstallDir\node_exporter-$NodeExporterVersion.windows-amd64"

# Step 5: Download and install NSSM
Write-Host "Downloading NSSM..." -ForegroundColor Cyan
Invoke-WebRequest -Uri $NssmUrl -OutFile $NssmZip
Expand-Archive -Path $NssmZip -DestinationPath $NssmExtract -Force

# Step 6: Install Node Exporter as a Windows Service
$nssmExe = Get-ChildItem -Recurse -Path $NssmExtract | Where-Object { $_.Name -eq "nssm.exe" } | Select-Object -First 1

if ($nssmExe) {
    Write-Host "Installing Node Exporter service..." -ForegroundColor Cyan
    & $nssmExe.FullName install $ServiceName "$InstallDir\node_exporter.exe"
} else {
    Write-Host "❌ Failed to find NSSM executable." -ForegroundColor Red
    exit 1
}

# Step 7: Open Firewall Port 9100
Write-Host "Opening Firewall port 9100..." -ForegroundColor Cyan
New-NetFirewallRule -DisplayName "Allow Node Exporter" -Direction Inbound -LocalPort 9100 -Protocol TCP -Action Allow

# Step 8: Start Node Exporter Service
Write-Host "Starting Node Exporter service..." -ForegroundColor Cyan
Start-Service -Name $ServiceName

# Step 9: Check Status
Write-Host "`nService Status:" -ForegroundColor Green
Get-Service -Name $ServiceName

Write-Host "`n✅ Node Exporter installed and running successfully!" -ForegroundColor Green
Write-Host "Access metrics at: http://<your-server-ip>:9100/metrics" -ForegroundColor Yellow
