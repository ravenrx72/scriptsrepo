<# 
.SYNOPSIS
  Guided incident intake → OpenAI Responses API → leadership email (if Critical)
  Requires: $env:OPENAI_API_KEY to be set.
#>

param(
  [string]$Model = "gpt-4.1"  # Change to any current text-capable model you have access to.
)

function Read-NonEmpty([string]$prompt) {
  do {
    $val = Read-Host $prompt
  } while ([string]::IsNullOrWhiteSpace($val))
  return $val
}

# 1) Collect inputs from analyst
$asset        = Read-NonEmpty "Asset name(s) (e.g., ComputerA, ComputerB)"
$class        = Read-NonEmpty "Classification (e.g., data breach, malware, app name)"
$scope        = Read-NonEmpty "Scope (e.g., 2 endpoints; 1 server; dept name)"
$severity     = Read-NonEmpty "Severity [Low | Medium | High | Critical]"

# Optional deeper context to improve accuracy
$detectedAt   = Read-Host "First detected (ISO 8601 recommended, e.g., 2025-11-05T13:45Z)"
$detectedBy   = Read-Host "Detected by (person/team/tool)"
$detectMethod = Read-Host "Detection method (alert, anomaly, user report, etc.)"
$dataType     = Read-Host "Data/system sensitivity (PII, PHI, prod, test, etc.)"
$businessFn   = Read-Host "Business function impacted (payments, customer portal, etc.)"
$vector       = Read-Host "Suspected vector (phishing, vuln CVE-XXXX, insider, unknown)"
$exfil        = Read-Host "Any indication of data exfiltration? (yes/no/unknown + details)"
$actions      = Read-Host "Actions taken so far (isolation, creds reset, triage, etc.)"
$regulatory   = Read-Host "Regulatory considerations (GDPR/HIPAA/state, unknown)"
$eta          = Read-Host "ETA for next update (e.g., 4 hours)"

# 2) Build the prompt for the model
$task = @"
You are a SOC Incident Communications assistant. 
Input details:
- Asset(s): $asset
- Classification: $class
- Scope: $scope
- Severity: $severity
- First detected: $detectedAt
- Detected by: $detectedBy
- Detection method: $detectMethod
- Data/System sensitivity: $dataType
- Business function: $businessFn
- Suspected vector: $vector
- Exfiltration signs: $exfil
- Actions taken: $actions
- Regulatory: $regulatory
- Next update ETA: $eta

Instructions:
1) If Severity is "Critical", produce an executive-ready leadership notification email with:
   - Clear subject line with severity, assets, and classification
   - One-paragraph summary
   - Bullet list: key facts (assets, classification, scope, severity, detection info)
   - Bullet list: immediate actions taken
   - Bullet list: next steps and ETA
   - Explicit "Requested leadership actions"
   - Signature block placeholders
2) If Severity is not Critical, return a concise incident summary (<= 180 words) suitable for internal IR channel.
3) Keep responses plain text (no markdown).
"@

# 3) Call OpenAI Responses API
if (-not $env:OPENAI_API_KEY) {
  Write-Error "OPENAI_API_KEY environment variable not set."
  exit 1
}

$headers = @{
  "Authorization" = "Bearer $($env:OPENAI_API_KEY)"      # Bearer auth per docs
  "Content-Type"  = "application/json"
}

$body = @{
  model = $Model
  # The Responses API accepts either a simple string or a multi-part input.
  input = @(
    @{
      role = "system"
      content = @(@{ type="text"; text = "You write incident communications with crisp, executive-friendly language." })
    },
    @{
      role = "user"
      content = @(@{ type="text"; text = $task })
    }
  )
  response_format = @{ type = "text" }  # Ask for plain text for easy copy/paste
}

try {
  $json = $body | ConvertTo-Json -Depth 8
  $resp = Invoke-RestMethod -Method Post -Uri "https://api.openai.com/v1/responses" -Headers $headers -Body $json

  # The Responses API provides a convenience field 'output_text' in most SDK/REST responses.
  if ($resp.output_text) {
    $text = $resp.output_text
  } else {
    # Fallback: stitch message parts if output_text is not present.
    $parts = @()
    foreach ($o in $resp.output) {
      if ($o.type -eq "message" -and $o.content) {
        foreach ($c in $o.content) {
          if ($c.type -eq "output_text" -or $c.type -eq "text") {
            $parts += $c.text
          }
        }
      }
    }
    $text = ($parts -join "`n")
  }

  "`n==== Model Response ====`n"
  $text
}
catch {
  Write-Error "API call failed: $($_.Exception.Message)"
  if ($_.Exception.Response) {
    $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
    $errBody = $reader.ReadToEnd()
    Write-Error "Server said: $errBody"
  }
  exit 1
}
