 (cd "$(git rev-parse --show-toplevel)" && git apply --3way <<'EOF' 
diff --git a/scripts/PS/SituationalAwareness.ps1 b/scripts/PS/SituationalAwareness.ps1
new file mode 100644
index 0000000000000000000000000000000000000000..c8da5f98be5a66557462f2e0b810d1f589957aee
--- /dev/null
+++ b/scripts/PS/SituationalAwareness.ps1
@@ -0,0 +1,317 @@
+<#
+.SYNOPSIS
+    Collects situational awareness data for the local system.
+
+.DESCRIPTION
+    Tests outbound connectivity for common ports, enumerates cached user profiles,
+    reports the system reboot time, prints summarized operating system details, and
+    inventories outbound firewall allow rules.
+
+.PARAMETER Ports
+    One or more TCP ports to test for outbound connectivity. Defaults to 22, 80, and 443.
+
+.PARAMETER PortTargets
+    A hashtable mapping port numbers to remote hosts that should be used when testing
+    connectivity for a specific port. Ports without an explicit mapping default to
+    the host defined by DefaultTestHost.
+
+.PARAMETER DefaultTestHost
+    The fallback host to test against when a port is not present in PortTargets.
+
+.PARAMETER ReportPath
+    Optional path where the collected data will be written as JSON for later review.
+
+.PARAMETER FirewallRuleLimit
+    Maximum number of outbound firewall allow rules to display and include in the
+    exported report.
+
+.NOTES
+    Requires administrative privileges for the most complete results. Some information
+    (such as security event logs) may be unavailable without elevation. Firewall rule
+    enumeration depends on the built-in NetSecurity module (available on Windows 8+
+    and Windows Server 2012+).
+#>
+[CmdletBinding()]
+param(
+    [Parameter()]
+    [int[]]$Ports = @(22, 80, 443),
+
+    [Parameter()]
+    [hashtable]$PortTargets = @{
+        22  = 'github.com'
+        80  = 'example.com'
+        443 = 'www.microsoft.com'
+        3389 = 'rdp.microsoft.com'
+    },
+
+    [Parameter()]
+    [string]$DefaultTestHost = '8.8.8.8',
+
+    [Parameter()]
+    [string]$ReportPath,
+
+    [Parameter()]
+    [ValidateRange(1, 2000)]
+    [int]$FirewallRuleLimit = 25
+)
+
+function Convert-FromCimDateTime {
+    [CmdletBinding()]
+    param(
+        [Parameter(Mandatory, ValueFromPipeline)]
+        [string]$CimDate
+    )
+
+    process {
+        if ([string]::IsNullOrWhiteSpace($CimDate)) {
+            return $null
+        }
+
+        try {
+            return [System.Management.ManagementDateTimeConverter]::ToDateTime($CimDate)
+        }
+        catch {
+            Write-Verbose "Failed to convert CIM datetime '$CimDate': $_"
+            return $null
+        }
+    }
+}
+
+function Convert-FirewallProfile {
+    [CmdletBinding()]
+    param(
+        [Parameter(ValueFromPipeline)]
+        [uint32]$Profile
+    )
+
+    process {
+        if ($Profile -eq 0) {
+            return 'Any'
+        }
+
+        $profileMap = [ordered]@{
+            1 = 'Domain'
+            2 = 'Private'
+            4 = 'Public'
+        }
+
+        $names = foreach ($mask in $profileMap.Keys) {
+            if ($Profile -band $mask) {
+                $profileMap[$mask]
+            }
+        }
+
+        if ($names) {
+            return ($names -join ', ')
+        }
+
+        return 'Custom'
+    }
+}
+
+function Test-OutboundPort {
+    [CmdletBinding()]
+    param(
+        [Parameter(Mandatory)]
+        [int]$Port,
+
+        [Parameter(Mandatory)]
+        [string]$Target
+    )
+
+    $result = [pscustomobject]@{
+        Port        = $Port
+        TargetHost  = $Target
+        Reachable   = $false
+        LatencyMs   = $null
+        Notes       = $null
+    }
+
+    $testNetConnection = Get-Command -Name Test-NetConnection -ErrorAction SilentlyContinue
+
+    try {
+        if ($testNetConnection) {
+            $test = Test-NetConnection -ComputerName $Target -Port $Port -WarningAction SilentlyContinue -ErrorAction Stop
+            $result.Reachable = [bool]$test.TcpTestSucceeded
+            $result.LatencyMs = $test.PingReplyDetails.RoundtripTime
+            if (-not $result.Reachable) {
+                $result.Notes = 'Test completed but port is not reachable.'
+            }
+        }
+        else {
+            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
+            $tcpClient = [System.Net.Sockets.TcpClient]::new()
+            $asyncResult = $tcpClient.BeginConnect($Target, $Port, $null, $null)
+            if (-not $asyncResult.AsyncWaitHandle.WaitOne([TimeSpan]::FromSeconds(5))) {
+                $tcpClient.Close()
+                throw "Connection attempt timed out."
+            }
+
+            $tcpClient.EndConnect($asyncResult)
+            $stopwatch.Stop()
+            $result.Reachable = $true
+            $result.LatencyMs = [math]::Round($stopwatch.Elapsed.TotalMilliseconds, 2)
+        }
+    }
+    catch {
+        $result.Notes = $_.Exception.Message
+    }
+
+    return $result
+}
+
+function Get-OutboundFirewallRules {
+    [CmdletBinding()]
+    param(
+        [Parameter()]
+        [ValidateRange(1, 2000)]
+        [int]$Limit = 25
+    )
+
+    try {
+        $rules = Get-NetFirewallRule -Direction Outbound -Enabled True -Action Allow -ErrorAction Stop
+    }
+    catch {
+        Write-Warning "Unable to retrieve outbound firewall rules: $_"
+        return @()
+    }
+
+    $rules
+        | Sort-Object -Property DisplayName
+        | Select-Object -First $Limit
+        | ForEach-Object {
+            $rule = $_
+            $portFilter = $rule | Get-NetFirewallPortFilter -ErrorAction SilentlyContinue
+            $addressFilter = $rule | Get-NetFirewallAddressFilter -ErrorAction SilentlyContinue
+
+            [pscustomobject]@{
+                DisplayName     = $rule.DisplayName
+                Name            = $rule.Name
+                Profiles        = Convert-FirewallProfile -Profile $rule.Profile
+                Protocol        = if ($portFilter.Protocol) { $portFilter.Protocol } else { 'Any' }
+                LocalPort       = if ($portFilter.LocalPort) { ($portFilter.LocalPort -join ', ') } else { 'Any' }
+                RemotePort      = if ($portFilter.RemotePort) { ($portFilter.RemotePort -join ', ') } else { 'Any' }
+                RemoteAddress   = if ($addressFilter.RemoteAddress) { ($addressFilter.RemoteAddress -join ', ') } else { 'Any' }
+                Program         = if ($rule.Program) { $rule.Program } else { 'Any' }
+                Service         = if ($rule.Service) { $rule.Service } else { 'Any' }
+            }
+        }
+}
+
+Write-Verbose 'Collecting outbound connectivity information.'
+$outboundConnectivity = foreach ($port in $Ports | Sort-Object -Unique) {
+    $target = if ($PortTargets.ContainsKey($port)) {
+        $PortTargets[$port]
+    }
+    else {
+        $DefaultTestHost
+    }
+
+    Test-OutboundPort -Port $port -Target $target
+}
+
+Write-Verbose 'Gathering outbound firewall allow rules.'
+$firewallRules = Get-OutboundFirewallRules -Limit $FirewallRuleLimit
+
+Write-Verbose 'Enumerating user profiles.'
+try {
+    $userProfiles = Get-CimInstance -ClassName Win32_UserProfile -ErrorAction Stop |
+        Where-Object { $_.Special -eq $false -and $_.LocalPath }
+}
+catch {
+    Write-Warning "Unable to enumerate user profiles via CIM: $_"
+    $userProfiles = @()
+}
+
+$userProfileReport = foreach ($profile in $userProfiles) {
+    $sid = $profile.SID
+    try {
+        $ntAccount = (New-Object System.Security.Principal.SecurityIdentifier($sid)).Translate([System.Security.Principal.NTAccount]).Value
+    }
+    catch {
+        $ntAccount = $sid
+    }
+
+    $lastUse = if ($profile.LastUseTime) {
+        Convert-FromCimDateTime -CimDate $profile.LastUseTime
+    }
+
+    [pscustomobject]@{
+        UserName     = $ntAccount
+        LocalPath    = $profile.LocalPath
+        LastLogon    = $lastUse
+        Loaded       = [bool]$profile.Loaded
+        IsRoaming    = [bool]$profile.RoamingConfigured
+    }
+}
+
+$cachedCredentialCount = ($userProfiles | Where-Object { $_.LastUseTime }).Count
+
+Write-Verbose 'Gathering system information.'
+try {
+    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
+    $computer = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
+}
+catch {
+    Write-Warning "Unable to gather CIM system information: $_"
+    $os = $null
+    $computer = $null
+}
+
+$lastBoot = if ($os) { Convert-FromCimDateTime -CimDate $os.LastBootUpTime }
+$uptime = if ($lastBoot) { (Get-Date) - $lastBoot }
+
+$systemInfo = [pscustomobject]@{
+    ComputerName = $env:COMPUTERNAME
+    Manufacturer = if ($computer) { $computer.Manufacturer } else { $null }
+    Model        = if ($computer) { $computer.Model } else { $null }
+    OSVersion    = if ($os) { $os.Caption } else { $null }
+    OSBuild      = if ($os) { $os.BuildNumber } else { $null }
+    LastBoot     = $lastBoot
+    Uptime       = $uptime
+}
+
+$report = [ordered]@{
+    GeneratedAt             = Get-Date
+    OutboundConnectivity    = $outboundConnectivity
+    FirewallRules           = $firewallRules
+    UserProfiles            = $userProfileReport
+    CachedCredentialCount   = $cachedCredentialCount
+    SystemInformation       = $systemInfo
+}
+
+if ($ReportPath) {
+    try {
+        $report | ConvertTo-Json -Depth 5 | Set-Content -Path $ReportPath -Encoding UTF8
+        Write-Host "Report data exported to $ReportPath"
+    }
+    catch {
+        Write-Warning "Failed to write report to $ReportPath: $_"
+    }
+}
+
+Write-Host '=== System Information ==='
+$systemInfo | Format-Table -AutoSize
+
+Write-Host '\n=== Outbound Connectivity Tests ==='
+$outboundConnectivity | Format-Table -AutoSize
+
+Write-Host ("\n=== Outbound Firewall Allow Rules (showing up to {0}) ===" -f $FirewallRuleLimit)
+if ($firewallRules.Count -gt 0) {
+    $firewallRules | Format-Table -AutoSize
+}
+else {
+    Write-Host 'No firewall allow rules were returned or the cmdlets are unavailable.'
+}
+
+Write-Host '\n=== User Profiles (Cached Credentials) ==='
+$userProfileReport | Sort-Object LastLogon -Descending | Format-Table -AutoSize
+
+if ($lastBoot) {
+    Write-Host "\nSystem last rebooted on: $($lastBoot.ToString('u'))"
+}
+else {
+    Write-Host '\nSystem last rebooted on: Unknown'
+}
+
+Write-Host "Cached credential profiles detected: $cachedCredentialCount" 
EOF
)