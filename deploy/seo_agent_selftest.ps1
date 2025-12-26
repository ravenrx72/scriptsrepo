param(
  [string]$SiteUrl    = "https://aicomply360.com",
  [string]$Username   = "aicomply360-bot",
  [string]$SecretPath = "C:\Users\josh\OneDrive\Documents\AIComply360\Marketing\seo\wp_app_pw.secret",
  [string]$LogPath    = "C:\Users\josh\OneDrive\Documents\AIComply360\Marketing\seo\seo_agent_selftest.log",
  [string]$OpenAIModel = "gpt-4o-mini-2024-07-18"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

# TLS 1.2 (Windows PowerShell 5.1)
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }

Add-Type -AssemblyName System.Net.Http

function Ensure-Directory {
  param([Parameter(Mandatory)][string]$Path)
  $dir = Split-Path -Parent $Path
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
}

function Write-Log {
  param([Parameter(Mandatory)][string]$Message, [ValidateSet("INFO","WARN","ERROR")] [string]$Level="INFO")
  Ensure-Directory -Path $LogPath
  $ts = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
  Add-Content -Path $LogPath -Value ("[{0}][{1}] {2}" -f $ts,$Level,$Message) -Encoding UTF8
}

function Step {
  param([Parameter(Mandatory)][string]$Name)
  Write-Host ("[STEP] {0}" -f $Name)
  Write-Log  ("STEP: {0}" -f $Name)
}

function Get-AppPasswordPlainOrPrompt {
  param([Parameter(Mandatory)][string]$SecretPath)

  if (Test-Path $SecretPath) {
    try {
      $enc  = (Get-Content -Path $SecretPath -Raw).Trim()
      $sec  = ConvertTo-SecureString $enc
      $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
      try { return [Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr) }
      finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
    } catch {
      Write-Log ("WARN: Secret decrypt failed; will prompt. Error: {0}" -f $_.Exception.Message) "WARN"
    }
  } else {
    Write-Log ("WARN: SecretPath not found; will prompt: {0}" -f $SecretPath) "WARN"
  }

  return (Read-Host "Paste WordPress application password (spaces OK)")
}

function New-BasicAuthHeader {
  param([string]$User, [string]$AppPasswordNoSpaces)
  $pair = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$User`:$AppPasswordNoSpaces"))
  return "Basic $pair"
}

function New-FormUrlEncodedBody {
  param([hashtable]$Data)
  $kv = New-Object System.Collections.Generic.List[string]
  foreach ($k in $Data.Keys) {
    $v = $Data[$k]
    if ($null -eq $v) { continue }
    $sv = [string]$v
    if ([string]::IsNullOrWhiteSpace($sv)) { continue }
    $kv.Add(("{0}={1}" -f [uri]::EscapeDataString([string]$k), [uri]::EscapeDataString($sv)))
  }
  return ($kv -join [string][char]38) # '&'
}

function Extract-OpenAIText {
  param($RespObj)

  if ($null -ne $RespObj.PSObject.Properties["output_text"] -and $RespObj.output_text) {
    return [string]$RespObj.output_text
  }

  if ($RespObj.output) {
    foreach ($o in @($RespObj.output)) {
      if ($o.content) {
        foreach ($c in @($o.content)) {
          if ($null -ne $c.PSObject.Properties["text"] -and $c.text) { return [string]$c.text }
          if ($null -ne $c.PSObject.Properties["output_text"] -and $c.output_text) { return [string]$c.output_text }
        }
      }
    }
  }

  throw "OpenAI response had no extractable text."
}

function Invoke-OpenAIResponses_HttpClient {
  param(
    [Parameter(Mandatory)][string]$Model,
    [Parameter(Mandatory)][string]$UserText  # IMPORTANT: do not name this Input
  )

  $k = $env:OPENAI_API_KEY
  if ([string]::IsNullOrWhiteSpace($k)) { throw "OPENAI_API_KEY is not visible in this process." }
  $k = $k.Trim()

  if ([string]::IsNullOrWhiteSpace($UserText)) {
    throw "UserText is empty; refusing to call OpenAI with missing input."
  }

  $client = New-Object System.Net.Http.HttpClient
  $client.DefaultRequestHeaders.Authorization = New-Object System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", $k)
  $client.DefaultRequestHeaders.Accept.Add((New-Object System.Net.Http.Headers.MediaTypeWithQualityHeaderValue("application/json")))

  $payloadObj = @{
    model = $Model
    input = $UserText
    max_output_tokens = 64
    temperature = 0.2
  }

  $payloadJson = $payloadObj | ConvertTo-Json -Depth 10
  Write-Log ("OpenAI payload preview: {0}" -f ($payloadJson.Substring(0, [Math]::Min(220, $payloadJson.Length))))

  $content = New-Object System.Net.Http.StringContent($payloadJson, [Text.Encoding]::UTF8, "application/json")
  $resp = $client.PostAsync("https://api.openai.com/v1/responses", $content).Result
  $body = $resp.Content.ReadAsStringAsync().Result

  if (-not $resp.IsSuccessStatusCode) {
    throw ("OpenAI HTTP {0}. Body: {1}" -f ([int]$resp.StatusCode), $body)
  }

  $obj = $body | ConvertFrom-Json
  return (Extract-OpenAIText -RespObj $obj)
}

function New-WpPost {
  param([string]$Site,[hashtable]$Headers,[string]$Title,[string]$HtmlContent)
  $body = @{ title=$Title; content=$HtmlContent; status="draft" } | ConvertTo-Json -Depth 10
  return (Invoke-RestMethod -Method POST -Uri "$Site/wp-json/wp/v2/posts" -Headers $Headers -ContentType "application/json" -Body $body)
}

function Set-RankMathMeta {
  param([string]$Site,[hashtable]$Headers,[int]$PostId,[string]$SeoTitle,[string]$SeoDescription,[string]$FocusKeyword)

  $form = @{
    post_id                 = $PostId
    rank_math_title         = $SeoTitle
    rank_math_description   = $SeoDescription
    rank_math_focus_keyword = $FocusKeyword
  }

  $encoded = New-FormUrlEncodedBody -Data $form
  return (Invoke-RestMethod -Method POST -Uri "$Site/wp-json/rank-math-api/v1/update-meta" -Headers $Headers -ContentType "application/x-www-form-urlencoded" -Body $encoded)
}

# ---------------------------
# Main
# ---------------------------
Ensure-Directory -Path $LogPath
Write-Log "Self-test started (v1.5)."
Write-Log ("PowerShell: {0}" -f $PSVersionTable.PSVersion.ToString())
Write-Log ("Model: {0}" -f $OpenAIModel)

try {
  Step "Confirm OPENAI_API_KEY visibility"
  $keyLen = if ($env:OPENAI_API_KEY) { $env:OPENAI_API_KEY.Trim().Length } else { 0 }
  Write-Host ("OPENAI_API_KEY length: {0}" -f $keyLen)
  Write-Log  ("OPENAI_API_KEY length: {0}" -f $keyLen)
  if ($keyLen -lt 20) { throw "OPENAI_API_KEY appears missing/too short in this process." }

  Step "Build WordPress auth header"
  $appPw = (Get-AppPasswordPlainOrPrompt -SecretPath $SecretPath) -replace "\s",""
  $wpHeaders = @{
    Authorization = (New-BasicAuthHeader -User $Username -AppPasswordNoSpaces $appPw)
    "User-Agent"  = "AIComply360-SEO-Agent-SelfTest/1.5"
  }

  Step "Call WordPress /users/me"
  $me = Invoke-RestMethod -Method GET -Uri "$SiteUrl/wp-json/wp/v2/users/me" -Headers $wpHeaders
  Write-Host ("WP users/me OK. id={0} name={1} slug={2}" -f $me.id,$me.name,$me.slug)
  Write-Log  ("WP users/me OK. id={0} name={1} slug={2}" -f $me.id,$me.name,$me.slug)

  Step "Call WordPress posts edit context"
  $null = Invoke-RestMethod -Method GET -Uri "$SiteUrl/wp-json/wp/v2/posts?per_page=1&context=edit" -Headers $wpHeaders
  Write-Host "WP posts edit-context OK."
  Write-Log  "WP posts edit-context OK."

  Step "Call OpenAI (Responses API) using HttpClient"
  $ai = Invoke-OpenAIResponses_HttpClient -Model $OpenAIModel -UserText "Say OK and nothing else."
  Write-Host ("OpenAI OK. Output: {0}" -f $ai)
  Write-Log  ("OpenAI OK. Output: {0}" -f $ai)

  Step "Create a draft post in WordPress"
  $stamp = (Get-Date).ToString("yyyyMMdd-HHmmss")
  $title = "SEO Agent SelfTest $stamp"
  $content = "<p><strong>Self-test:</strong> WordPress + OpenAI are working.</p><p>OpenAI says: $ai</p>"
  $post = New-WpPost -Site $SiteUrl -Headers $wpHeaders -Title $title -HtmlContent $content
  Write-Host ("WP create OK. post_id={0} link={1}" -f $post.id,$post.link)
  Write-Log  ("WP create OK. post_id={0} link={1}" -f $post.id,$post.link)

  Step "Update Rank Math meta for the draft"
  $null = Set-RankMathMeta -Site $SiteUrl -Headers $wpHeaders -PostId ([int]$post.id) -SeoTitle $title -SeoDescription "Self-test confirming OpenAI + WP API." -FocusKeyword "seo agent selftest"
  Write-Log "Rank Math meta OK."

  Write-Log "Self-test complete: SUCCESS."
  Write-Host "SUCCESS"
  Write-Host ("Created draft: {0}" -f $post.link)
}
catch {
  $msg = $_.Exception.Message
  Write-Log ("Self-test FAILED: {0}" -f $msg) "ERROR"
  Write-Host "FAILED"
  Write-Host $msg
  Write-Host ("Log file: {0}" -f $LogPath)
  exit 1
}

