# Ensure we are in the src directory
Set-Location $PSScriptRoot

$processes = @()

try {
    Write-Host "Starting Products Service..."
    $p1 = Start-Process dotnet -ArgumentList "run --project ProductsService --urls=http://localhost:5001" -PassThru -NoNewWindow
    $processes += $p1

    Write-Host "Starting Reviews Service..."
    $p2 = Start-Process dotnet -ArgumentList "run --project ReviewsService --urls=http://localhost:5002" -PassThru -NoNewWindow
    $processes += $p2

    Write-Host "Starting Shipping Service..."
    $p3 = Start-Process dotnet -ArgumentList "run --project ShippingService --urls=http://localhost:5003" -PassThru -NoNewWindow
    $processes += $p3

    Write-Host "Starting Orders Service..."
    $p5 = Start-Process dotnet -ArgumentList "run --project OrdersService --urls=http://localhost:5004" -PassThru -NoNewWindow
    $processes += $p5

    Write-Host "Starting BackOffice Service..."
    $p6 = Start-Process dotnet -ArgumentList "run --project BackOfficeService" -PassThru -NoNewWindow
    $processes += $p6

    Write-Host "Starting Gateway..."
    $p4 = Start-Process dotnet -ArgumentList "run --project Gateway --urls=http://localhost:5000" -PassThru -NoNewWindow
    $processes += $p4

    Write-Host "Starting Frontend..."
    $frontendPath = Join-Path $PSScriptRoot "..\frontend"
    
    $isWindows = $env:OS -like "*Windows*" -or $IsWindows
    if ($isWindows) {
        $pFrontend = Start-Process "cmd.exe" -ArgumentList "/c npm run dev" -WorkingDirectory $frontendPath -PassThru -NoNewWindow
    } else {
        $pFrontend = Start-Process "npm" -ArgumentList "run dev" -WorkingDirectory $frontendPath -PassThru -NoNewWindow
    }
    $processes += $pFrontend

    Write-Host "Waiting for services to initialize..."
    Start-Sleep -Seconds 5

    Write-Host "Opening Gateway in Browser..."
    Start-Process "http://localhost:5000/graphql"
    
    Write-Host "Opening Frontend in Browser..."
    Start-Process "http://localhost:5173"

    Write-Host "----------------------------------------------------------------"
    Write-Host "Services are running. Press 'Q' or Ctrl+C to stop all services."
    Write-Host "----------------------------------------------------------------"

    while ($true) {
        if ($host.UI.RawUI.KeyAvailable) {
            $key = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            if ($key.Character -eq 'q' -or $key.Character -eq 'Q') {
                break
            }
        }
        Start-Sleep -Milliseconds 500
        
        # Check if any process exited unexpectedly
        foreach ($proc in $processes) {
            if ($proc.HasExited) {
                Write-Warning "Process $($proc.Id) has exited unexpectedly."
            }
        }
    }
}
finally {
    Write-Host "Stopping services..."
    foreach ($proc in $processes) {
        if ($proc -and -not $proc.HasExited) {
            Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
        }
    }
    Write-Host "All services stopped."
}
