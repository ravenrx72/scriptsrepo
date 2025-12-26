<#
AIComply360 SEO Agent - STRICT-SIMPLE-3.5 (REVERT + PS5.1 SAFE)
- CSV required columns: keyword, status
- Updates: status, wp_post_id, wp_link, last_run_utc, notes

Key properties:
- Uses OpenAI Responses API
- StrictMode-safe parsing (no direct access of optional fields)
- WP REST calls use -DisableKeepAlive (PS 5.1 safe)
#>

param(
  [string]$SiteUrl   = "https://aicomply360.com",
  [string]$Username  = "aicomply360-bot",

  [string]$CsvPath   = "C:\Users\josh\OneDrive\Documents\AIComply360\Marketing\seo\seo.csv",
  [string]$SecretPath = "C:\Users\josh\OneDrive\Documents\AIComply360\Marketing\seo\wp_app_pw.secret",
  [string]$LogPath   = "C:\Users\josh\OneDrive\Documents\AIComply360\Marketing\seo\seo_simple.log",

  [int]$MaxItems = 1,
  [ValidateSet("draft","publish")]
  [string]$Mode = "draft",

  # OpenAI models
  [string]$TextModel  = "gpt-4o-mini-2024-07-18",
  [string]$ImageModel = "gpt-image-1",

  # Strict QA
  [int]$MinWordCount = 1100,
  [int]$MinH2Count   = 10,
  [int]$MinKeywordExactMatches = 6,
  [int]$MaxAttempts  = 6,

  # Image behavior (reverted: no style param)
  [switch]$AutoImage = $true,
  [switch]$RequireImage = $false
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }
try { [Net.ServicePointManager]::Expect100Continue = $false } catch { }
try { [Net.ServicePointManager]::DefaultConnectionLimit = 50 } catch { }

$ScriptVersion = "STRICT-SIMPLE-3.5-REVERT-PS51"

# ---------- Utilities ----------
function Ensure-Directory {
  param([Parameter(Mandatory=$true)][string]$Path)
  $dir = Split-Path -Parent $Path
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
}

function Write-Log {
  param([Parameter(Mandatory=$true)][string]$Message, [ValidateSet("INFO","WARN","ERROR")] [string]$Level="INFO")
  Ensure-Directory -Path $LogPath
  $ts = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
  Add-Content -Path $LogPath -Value ("[{0}][{1}] {2}" -f $ts,$Level,$Message) -Encoding UTF8
}

function As-String {
  param([object]$o)
  if ($null -eq $o) { return "" }
  return [string]$o
}

function Try-GetProp {
  param([object]$Obj,[string]$Name)
  if ($null -eq $Obj) { return $null }
  try {
    $p = $Obj.PSObject.Properties[$Name]
    if ($null -ne $p) { return $p.Value }
  } catch { }
  return $null
}

function Get-PropString {
  param([object]$Obj,[string]$Name)
  return (As-String (Try-GetProp -Obj $Obj -Name $Name))
}

function Ensure-Column {
  param([object]$Row,[string]$Name,[string]$Default="")
  if (-not $Row.PSObject.Properties.Match($Name)) {
    $Row | Add-Member -NotePropertyName $Name -NotePropertyValue $Default
  }
}

function Save-CsvAtomic {
  param([Parameter(Mandatory=$true)][object[]]$Rows, [Parameter(Mandatory=$true)][string]$Path)
  Ensure-Directory -Path $Path
  $tmp = "{0}.tmp" -f $Path
  $Rows | Export-Csv -Path $tmp -NoTypeInformation -Encoding UTF8
  Move-Item -Path $tmp -Destination $Path -Force
}

function New-BasicAuthHeader {
  param([string]$User, [string]$AppPasswordNoSpaces)
  $pair = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$User`:$AppPasswordNoSpaces"))
  return "Basic $pair"
}

function Get-AppPasswordPlain {
  param([Parameter(Mandatory=$true)][string]$SecretPath)
  if (-not (Test-Path $SecretPath)) { throw "Secret file not found: $SecretPath" }
  $enc  = (Get-Content -Path $SecretPath -Raw).Trim()
  $sec  = ConvertTo-SecureString $enc
  $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
  try { return [Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr) }
  finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}

function Get-ErrDetail {
  param($ErrRecord)
  $msg = ""
  try { $msg = [string]$ErrRecord.Exception.Message } catch { }
  $ln = ""
  $line = ""
  try {
    if ($ErrRecord.InvocationInfo) {
      $ln = $ErrRecord.InvocationInfo.ScriptLineNumber
      $line = $ErrRecord.InvocationInfo.Line
    }
  } catch { }
  if ($ln) { return ("{0} (line {1}): {2}" -f $msg,$ln,$line) }
  return $msg
}

function Sanitize-OpenAIText {
  param([Parameter(Mandatory=$true)][string]$Text)
  $t = (As-String $Text).Trim()
  $t = [regex]::Replace($t, "^\s*```[a-zA-Z0-9_-]*\s*", "", "Singleline")
  $t = [regex]::Replace($t, "\s*```\s*$", "", "Singleline")
  return $t.Trim()
}

# ---------- OpenAI (Responses API) ----------
function Model-SupportsTemperature {
  param([string]$Model)
  $m = (As-String $Model).ToLowerInvariant()
  if ($m -like "gpt-5*") { return $false }
  return $true
}

function Extract-ResponsesText {
  param([object]$RespObj)

  # Some responses include an aggregate text field; read via property-bag only.
  $agg = Try-GetProp -Obj $RespObj -Name "output_text"
  if (-not [string]::IsNullOrWhiteSpace((As-String $agg))) { return (As-String $agg) }

  # Standard responses: output[] -> content[] -> text
  $out = Try-GetProp -Obj $RespObj -Name "output"
  foreach ($o in @($out)) {
    $content = Try-GetProp -Obj $o -Name "content"
    foreach ($c in @($content)) {
      $t1 = Try-GetProp -Obj $c -Name "text"
      if (-not [string]::IsNullOrWhiteSpace((As-String $t1))) { return (As-String $t1) }

      $type = (Get-PropString $c "type").ToLowerInvariant()
      if ($type -eq "output_text") {
        $t2 = Try-GetProp -Obj $c -Name "text"
        if (-not [string]::IsNullOrWhiteSpace((As-String $t2))) { return (As-String $t2) }
      }
    }
  }

  $id = Get-PropString $RespObj "id"
  $model = Get-PropString $RespObj "model"
  throw ("OpenAI response had no extractable text. id={0} model={1}" -f $id,$model)
}

function Invoke-OpenAIResponses {
  param(
    [Parameter(Mandatory=$true)][string]$Model,
    [Parameter(Mandatory=$true)][string]$Prompt,
    [int]$MaxOutputTokens = 2200,
    [double]$Temperature = 0.25
  )

  $k = (As-String $env:OPENAI_API_KEY).Trim()
  if ([string]::IsNullOrWhiteSpace($k)) { throw "OPENAI_API_KEY is not set in this process environment." }

  $p = (As-String $Prompt).Trim()
  if ([string]::IsNullOrWhiteSpace($p)) { throw "Refusing OpenAI call: prompt is empty." }

  $supportsTemp = Model-SupportsTemperature -Model $Model

  $headers = @{
    Authorization = "Bearer $k"
    "Content-Type" = "application/json"
  }

  $payload = @{
    model = $Model
    input = $p
    max_output_tokens = $MaxOutputTokens
  }
  if ($supportsTemp) { $payload.temperature = $Temperature }

  Write-Log ("OpenAI Responses call model={0} temp_sent={1} max_out={2} prompt_len={3}" -f $Model,$supportsTemp,$MaxOutputTokens,$p.Length)

  $resp = Invoke-RestMethod -Method POST -Uri "https://api.openai.com/v1/responses" -Headers $headers `
    -Body ($payload | ConvertTo-Json -Depth 12) -TimeoutSec 180 -DisableKeepAlive

  return (Extract-ResponsesText -RespObj $resp)
}

function Invoke-OpenAIWithRetry {
  param(
    [Parameter(Mandatory=$true)][string]$Model,
    [Parameter(Mandatory=$true)][string]$Prompt,
    [int]$MaxOutputTokens = 2200,
    [double]$Temperature = 0.25,
    [int]$Retries = 3
  )

  for ($i=1; $i -le $Retries; $i++) {
    try {
      return (Invoke-OpenAIResponses -Model $Model -Prompt $Prompt -MaxOutputTokens $MaxOutputTokens -Temperature $Temperature)
    }
    catch {
      Write-Log ("OpenAI call failed (attempt {0}/{1}): {2}" -f $i,$Retries,$_.Exception.Message) "WARN"
      if ($i -eq $Retries) { throw }
      Start-Sleep -Seconds (2 * $i)
    }
  }
}

# ---------- WordPress helpers (PS 5.1 safe) ----------
$TermCache = @{
  categories = @{}
  tags       = @{}
}

function Normalize-Slug {
  param([string]$s)
  $x = (As-String $s).Trim().ToLowerInvariant()
  $x = [regex]::Replace($x, "[^a-z0-9\s-]", "")
  $x = [regex]::Replace($x, "\s+", "-")
  $x = [regex]::Replace($x, "-{2,}", "-")
  $x = $x.Trim("-")
  if ($x.Length -gt 60) { $x = $x.Substring(0,60).Trim("-") }
  if ([string]::IsNullOrWhiteSpace($x)) { $x = "untitled" }
  return $x
}

function Normalize-TermName {
  param([string]$s,[int]$Max=60)
  $n = (As-String $s).Trim()
  $n = [regex]::Replace($n, "\s+", " ")
  if ($n.Length -gt $Max) { $n = $n.Substring(0,$Max).Trim() }
  if ([string]::IsNullOrWhiteSpace($n)) { $n = "Untitled" }
  return $n
}

function Get-WpTermsSearch {
  param([string]$Site,[hashtable]$Headers,[ValidateSet("categories","tags")] [string]$Tax,[string]$Search)
  $q = [uri]::EscapeDataString($Search)
  $uri = "{0}/wp-json/wp/v2/{1}?per_page=100&search={2}&context=edit" -f $Site,$Tax,$q
  return @(Invoke-RestMethod -Method GET -Uri $uri -Headers $Headers -TimeoutSec 120 -DisableKeepAlive)
}

function Get-WpTermIdBySlug {
  param([string]$Site,[hashtable]$Headers,[ValidateSet("categories","tags")] [string]$Tax,[string]$Slug)

  $slugN = Normalize-Slug $Slug
  if ($TermCache[$Tax].ContainsKey($slugN)) { return [int]$TermCache[$Tax][$slugN] }

  $terms = Get-WpTermsSearch -Site $Site -Headers $Headers -Tax $Tax -Search ($slugN.Replace("-"," "))
  foreach ($t in $terms) {
    $tslug = Get-PropString $t "slug"
    if (-not [string]::IsNullOrWhiteSpace($tslug) -and $tslug -eq $slugN) {
      $id = [int](Get-PropString $t "id")
      if ($id -gt 0) { $TermCache[$Tax][$slugN] = $id; return $id }
    }
  }
  return 0
}

function Get-WpTermIdByName {
  param([string]$Site,[hashtable]$Headers,[ValidateSet("categories","tags")] [string]$Tax,[string]$Name)

  $nameN = Normalize-TermName $Name 60
  $terms = Get-WpTermsSearch -Site $Site -Headers $Headers -Tax $Tax -Search $nameN
  foreach ($t in $terms) {
    $tname = Get-PropString $t "name"
    if (-not [string]::IsNullOrWhiteSpace($tname) -and $tname.ToLowerInvariant() -eq $nameN.ToLowerInvariant()) {
      $id = [int](Get-PropString $t "id")
      if ($id -gt 0) { return $id }
    }
  }
  return 0
}

function Read-WpErrorBody {
  param($ErrRecord)
  $respBody = ""
  $status = ""
  try {
    $webResp = $ErrRecord.Exception.Response
    if ($webResp) {
      $status = $webResp.StatusCode.value__
      $sr = New-Object System.IO.StreamReader($webResp.GetResponseStream())
      $respBody = $sr.ReadToEnd()
      $sr.Close()
    }
  } catch { }
  return @{ Status=$status; Body=$respBody }
}

function New-WpTerm {
  param([string]$Site,[hashtable]$Headers,[ValidateSet("categories","tags")] [string]$Tax,[string]$Name,[string]$Slug,[int]$Parent=0)

  $nameN = Normalize-TermName $Name 60
  $slugN = Normalize-Slug $Slug

  $body = @{ name = $nameN; slug = $slugN }
  if ($Tax -eq "categories" -and $Parent -gt 0) { $body.parent = $Parent }

  $uri = "{0}/wp-json/wp/v2/{1}" -f $Site,$Tax

  try {
    $created = Invoke-RestMethod -Method POST -Uri $uri -Headers $Headers -ContentType "application/json" `
      -Body ($body | ConvertTo-Json -Depth 8) -TimeoutSec 120 -DisableKeepAlive
    $id = [int](Get-PropString $created "id")
    if ($id -gt 0) { $TermCache[$Tax][$slugN] = $id }
    return $id
  }
  catch {
    $e = Read-WpErrorBody -ErrRecord $_
    if (-not [string]::IsNullOrWhiteSpace($e.Body)) {
      Write-Log ("WP term create failed tax={0} name='{1}' slug='{2}' HTTP {3}. Body: {4}" -f $Tax,$nameN,$slugN,$e.Status,$e.Body) "ERROR"
      try {
        $errObj = $e.Body | ConvertFrom-Json
        if ($errObj.code -eq "term_exists" -and $errObj.data -and $errObj.data.term_id) {
          $existingId = [int]$errObj.data.term_id
          $TermCache[$Tax][$slugN] = $existingId
          Write-Log ("WP term_exists handled tax={0} slug='{1}' -> id={2}" -f $Tax,$slugN,$existingId) "WARN"
          return $existingId
        }
      } catch { }
      throw ("WP term create failed HTTP {0}. Body: {1}" -f $e.Status,$e.Body)
    }
    throw
  }
}

function Ensure-WpTerm {
  param([string]$Site,[hashtable]$Headers,[ValidateSet("categories","tags")] [string]$Tax,[string]$Name,[string]$Slug,[int]$Parent=0)

  $nameN = Normalize-TermName $Name 60
  $slugN = Normalize-Slug $Slug

  $idBySlug = Get-WpTermIdBySlug -Site $Site -Headers $Headers -Tax $Tax -Slug $slugN
  if ($idBySlug -gt 0) { return $idBySlug }

  $idByName = Get-WpTermIdByName -Site $Site -Headers $Headers -Tax $Tax -Name $nameN
  if ($idByName -gt 0) { $TermCache[$Tax][$slugN] = $idByName; return $idByName }

  return (New-WpTerm -Site $SiteUrl -Headers $Headers -Tax $Tax -Name $nameN -Slug $slugN -Parent $Parent)
}

function Upload-WpMediaFromBytes {
  param([string]$Site,[hashtable]$Headers,[byte[]]$Bytes,[string]$FileName,[string]$AltText)

  $uri = "{0}/wp-json/wp/v2/media" -f $Site
  $h = @{}
  foreach ($k in $Headers.Keys) { $h[$k] = $Headers[$k] }
  $h["Content-Disposition"] = "attachment; filename=$FileName"

  $media = Invoke-RestMethod -Method POST -Uri $uri -Headers $h -ContentType "image/png" -Body $Bytes `
    -TimeoutSec 180 -DisableKeepAlive
  $id = [int](Get-PropString $media "id")

  if ($id -gt 0 -and -not [string]::IsNullOrWhiteSpace($AltText)) {
    try {
      $u = "{0}/wp-json/wp/v2/media/{1}" -f $Site,$id
      $body = @{ alt_text = $AltText }
      $null = Invoke-RestMethod -Method POST -Uri $u -Headers $Headers -ContentType "application/json" `
        -Body ($body | ConvertTo-Json -Depth 6) -TimeoutSec 120 -DisableKeepAlive
    } catch { }
  }

  return $id
}

function New-WpPost {
  param(
    [string]$Site,[hashtable]$Headers,
    [string]$Title,[string]$Html,[string]$Status,[string]$Slug,
    [int[]]$CategoryIds,[int[]]$TagIds,
    [int]$FeaturedMediaId = 0
  )

  $body = @{
    title   = $Title
    content = $Html
    status  = $Status
  }
  if (-not [string]::IsNullOrWhiteSpace($Slug)) { $body.slug = $Slug }
  if ($CategoryIds -and $CategoryIds.Count -gt 0) { $body.categories = $CategoryIds }
  if ($TagIds -and $TagIds.Count -gt 0) { $body.tags = $TagIds }
  if ($FeaturedMediaId -gt 0) { $body.featured_media = $FeaturedMediaId }

  $uri = "{0}/wp-json/wp/v2/posts" -f $Site
  return (Invoke-RestMethod -Method POST -Uri $uri -Headers $Headers -ContentType "application/json" `
    -Body ($body | ConvertTo-Json -Depth 10) -TimeoutSec 180 -DisableKeepAlive)
}

function Set-RankMathMeta {
  param([string]$Site,[hashtable]$Headers,[int]$PostId,[string]$SeoTitle,[string]$SeoDescription,[string]$FocusKeyword)

  $pairs = @()
  $pairs += "post_id=$([uri]::EscapeDataString([string]$PostId))"
  $pairs += "rank_math_title=$([uri]::EscapeDataString($SeoTitle))"
  $pairs += "rank_math_description=$([uri]::EscapeDataString($SeoDescription))"
  $pairs += "rank_math_focus_keyword=$([uri]::EscapeDataString($FocusKeyword))"

  $body = ($pairs -join "&")
  $uri = "{0}/wp-json/rank-math-api/v1/update-meta" -f $Site
  $null = Invoke-RestMethod -Method POST -Uri $uri -Headers $Headers -ContentType "application/x-www-form-urlencoded" `
    -Body $body -TimeoutSec 120 -DisableKeepAlive
}

# ---------- QA helpers ----------
function Strip-HtmlWords {
  param([string]$Html)
  $text = ($Html -replace "<[^>]+>"," ") -replace "\s+"," "
  return ($text.Trim().Split(" ", [System.StringSplitOptions]::RemoveEmptyEntries)).Count
}

function Count-H2 {
  param([string]$Html)
  return ([regex]::Matches($Html, "<h2\b", "IgnoreCase")).Count
}

function Count-ExactKeywordMatches {
  param([string]$Html,[string]$Keyword)
  $kw = (As-String $Keyword).ToLowerInvariant().Trim()
  $htmlLower = (As-String $Html).ToLowerInvariant()
  return ([regex]::Matches($htmlLower, [regex]::Escape($kw))).Count
}

function Validate-Content {
  param([string]$Html,[string]$Keyword,[int]$MinWords,[int]$MinH2,[int]$MinKwMatches)

  $problems = New-Object System.Collections.Generic.List[string]
  if ([string]::IsNullOrWhiteSpace($Html)) { $problems.Add("Empty HTML."); return $problems.ToArray() }

  $wc = Strip-HtmlWords -Html $Html
  if ($wc -lt $MinWords) { $problems.Add(("Word count {0} < {1}" -f $wc,$MinWords)) }

  $h2 = Count-H2 -Html $Html
  if ($h2 -lt $MinH2) { $problems.Add(("H2 count {0} < {1}" -f $h2,$MinH2)) }

  $kwc = Count-ExactKeywordMatches -Html $Html -Keyword $Keyword
  if ($kwc -lt $MinKwMatches) { $problems.Add(("Keyword matches {0} < {1}" -f $kwc,$MinKwMatches)) }

  if (-not [regex]::IsMatch($Html, "<h2>\s*FAQ\s*</h2>", "IgnoreCase")) {
    $problems.Add("Missing <h2>FAQ</h2> section.")
  }

  return $problems.ToArray()
}

# ---------- Prompt builders ----------
function Build-PlanPrompt {
  param([string]$Keyword)

@"
Return ONLY valid JSON. No markdown. No commentary.

You are an SEO SME and ISO/IEC 27001:2022 implementation expert writing for AIComply360.com.
Primary keyword (exact phrase): "$Keyword"

Create a plan for ONE blog post with:
- title
- slug (lowercase, hyphens, <= 60 chars)
- seo_title (<= 60 chars)
- seo_description (<= 160 chars)
- focus_keyword (same as primary keyword)
- category (ONE): { "name": "...", "slug": "..." }
- tags (5 to 8): [ { "name": "...", "slug": "..." }, ... ]
- image_prompt (clean modern cybersecurity illustration prompt; no text; no logos)

Rules:
- Always include tags for "ISO 27001" and "Startups".
- Slugs must be lowercase, <= 60 chars.

JSON schema:
{
  "title": "string",
  "slug": "string",
  "seo_title": "string",
  "seo_description": "string",
  "focus_keyword": "string",
  "category": { "name": "string", "slug": "string" },
  "tags": [ { "name": "string", "slug": "string" } ],
  "image_prompt": "string"
}
"@
}

function Build-ArticlePrompt {
  param([object]$Plan,[string]$Keyword,[int]$MinH2,[int]$MinKw)

  $title = Get-PropString $Plan "title"

@"
You are a senior SEO content strategist and ISO/IEC 27001:2022 implementation SME writing for AIComply360.com.

PRIMARY KEYWORD (exact phrase): $Keyword
TITLE (WordPress will use as H1): $title

NON-NEGOTIABLE OUTPUT RULES:
- Output ONLY valid HTML. No Markdown.
- Do NOT wrap output in triple backticks, and do NOT include a language label.
- Do NOT include <h1> anywhere.
- Start with one short <p> intro that uses the EXACT keyword once.
- Length target: 1800-2400 words.
- Include at least $MinH2 <h2> sections.
- Include at least 6 <h3> sections.
- Include <h2>Common Mistakes (Startups)</h2> with 10+ bullet items.
- Include <h2>Evidence Examples Auditors Sample</h2> with 14+ bullet items.
- Include <h2>FAQ</h2> with exactly 6 <h3> questions and short answers.
- End with a CTA linking to https://aicomply360.com

KEYWORD RULE:
- Use the EXACT phrase "$Keyword" at least $MinKw times.

Return ONLY the HTML.
"@
}

function Build-ExpandPrompt {
  param([string]$Keyword,[string[]]$Issues,[string]$ExistingHtml,[int]$MinH2,[int]$MinKw)

  $issuesText = ($Issues -join " | ")

@"
You produced HTML that failed QA for the keyword "$Keyword".

QA FAILURES: $issuesText

Rewrite and expand to pass QA. Output ONLY HTML. No Markdown.
Do NOT wrap output in triple backticks, and do NOT include a language label.
Do NOT include <h1>.

Ensure:
- 1800-2400 words
- at least $MinH2 H2 sections
- at least 6 H3 sections
- include <h2>FAQ</h2> with exactly 6 <h3> questions
- use the EXACT phrase "$Keyword" at least $MinKw times

Current HTML:
$ExistingHtml
"@
}

# ---------- OpenAI image generation ----------
function Invoke-OpenAIImage {
  param([Parameter(Mandatory=$true)][string]$Prompt,[string]$Size="1024x1024",[string]$Model="gpt-image-1")

  $k = (As-String $env:OPENAI_API_KEY).Trim()
  if ([string]::IsNullOrWhiteSpace($k)) { throw "OPENAI_API_KEY is not set in this process environment." }

  $p = (As-String $Prompt).Trim()
  if ([string]::IsNullOrWhiteSpace($p)) { throw "Refusing image call: prompt is empty." }

  $headers = @{
    Authorization = "Bearer $k"
    "Content-Type" = "application/json"
  }

  $payload = @{
    model  = $Model
    prompt = $p
    size   = $Size
  }

  Write-Log ("OpenAI Images call model={0} size={1} prompt_len={2}" -f $Model,$Size,$p.Length)

  $resp = Invoke-RestMethod -Method POST -Uri "https://api.openai.com/v1/images/generations" -Headers $headers `
    -Body ($payload | ConvertTo-Json -Depth 8) -TimeoutSec 180 -DisableKeepAlive

  $data = Try-GetProp -Obj $resp -Name "data"
  if (-not $data -or @($data).Count -lt 1) { throw "Image response missing data." }

  $b64 = Try-GetProp -Obj (@($data)[0]) -Name "b64_json"
  if ([string]::IsNullOrWhiteSpace((As-String $b64))) { throw "Image response missing b64_json." }

  return [Convert]::FromBase64String((As-String $b64))
}

# ---------- Main ----------
Write-Log ("Starting seo_agent_simple {0}. ScriptPath={1} CsvPath={2} MaxItems={3} Mode={4} TextModel={5} AutoImage={6}" -f `
  $ScriptVersion,$PSCommandPath,$CsvPath,$MaxItems,$Mode,$TextModel,$AutoImage.IsPresent)

if (-not (Test-Path $CsvPath)) { throw "CSV not found: $CsvPath" }

$appPw = (Get-AppPasswordPlain -SecretPath $SecretPath) -replace "\s",""
$wpHeaders = @{
  Authorization = (New-BasicAuthHeader -User $Username -AppPasswordNoSpaces $appPw)
  "User-Agent"  = "AIComply360-SEO-Agent/$ScriptVersion"
}

# WP auth check (PS 5.1 safe; no Connection header)
$me = Invoke-RestMethod -Method GET -Uri ("{0}/wp-json/wp/v2/users/me" -f $SiteUrl) -Headers $wpHeaders -TimeoutSec 120 -DisableKeepAlive
Write-Log ("WP auth OK user={0} id={1}" -f (Get-PropString $me "slug"),(Get-PropString $me "id"))

$rows = @(Import-Csv -Path $CsvPath)
foreach ($r in $rows) {
  Ensure-Column -Row $r -Name "status" -Default ""
  Ensure-Column -Row $r -Name "keyword" -Default ""
  Ensure-Column -Row $r -Name "slug" -Default ""
  Ensure-Column -Row $r -Name "wp_post_id" -Default ""
  Ensure-Column -Row $r -Name "wp_link" -Default ""
  Ensure-Column -Row $r -Name "last_run_utc" -Default ""
  Ensure-Column -Row $r -Name "notes" -Default ""

  $r.status  = (As-String $r.status).Trim()
  $r.keyword = (As-String $r.keyword).Trim()
  $r.slug    = (As-String $r.slug).Trim()
}

$eligible = @($rows | Where-Object {
  $s = (As-String $_.status).ToLowerInvariant()
  ([string]::IsNullOrWhiteSpace($s)) -or ($s -eq "pending") -or ($s -eq "queued")
} | Where-Object { -not [string]::IsNullOrWhiteSpace((As-String $_.keyword)) } | Select-Object -First $MaxItems)

Write-Log ("Eligible pending rows: {0}" -f $eligible.Count)
if ($eligible.Count -eq 0) { Write-Log "No pending rows found. Exiting."; exit 0 }

foreach ($item in $eligible) {
  $kw = (As-String $item.keyword).Trim()
  $nowUtc = (Get-Date).ToUniversalTime().ToString("o")

  try {
    Write-Log ("Processing keyword='{0}'" -f $kw)

    # 1) Plan JSON
    $planPrompt = Build-PlanPrompt -Keyword $kw
    $planRaw = Invoke-OpenAIWithRetry -Model $TextModel -Prompt $planPrompt -MaxOutputTokens 700 -Temperature 0.20 -Retries 3
    $planRaw = Sanitize-OpenAIText -Text $planRaw
    $plan = $planRaw | ConvertFrom-Json

    $title = (Get-PropString $plan "title").Trim()
    if ([string]::IsNullOrWhiteSpace($title)) { throw "Plan missing title." }

    $slug = (Get-PropString $plan "slug").Trim()
    if ([string]::IsNullOrWhiteSpace($slug)) { $slug = Normalize-Slug $title }
    $slug = Normalize-Slug $slug
    if ([string]::IsNullOrWhiteSpace($item.slug)) { $item.slug = $slug }

    # 2) Taxonomy
    $catObj  = Try-GetProp -Obj $plan -Name "category"
    $catName = Normalize-TermName (Get-PropString $catObj "name") 60
    $catSlug = Normalize-Slug (Get-PropString $catObj "slug")
    if ([string]::IsNullOrWhiteSpace($catName)) { $catName = "ISO 27001" }
    if ([string]::IsNullOrWhiteSpace($catSlug)) { $catSlug = Normalize-Slug $catName }

    $catId = Ensure-WpTerm -Site $SiteUrl -Headers $wpHeaders -Tax "categories" -Name $catName -Slug $catSlug -Parent 0

    $tagIds = New-Object System.Collections.Generic.List[int]
    $tags = Try-GetProp -Obj $plan -Name "tags"
    foreach ($t in @($tags)) {
      $tn = Normalize-TermName (Get-PropString $t "name") 60
      $ts = Normalize-Slug (Get-PropString $t "slug")
      if ([string]::IsNullOrWhiteSpace($tn)) { continue }
      if ([string]::IsNullOrWhiteSpace($ts)) { $ts = Normalize-Slug $tn }
      $id = Ensure-WpTerm -Site $SiteUrl -Headers $wpHeaders -Tax "tags" -Name $tn -Slug $ts -Parent 0
      if ($id -gt 0) { $tagIds.Add($id) }
    }

    if ($tagIds.Count -lt 2) {
      $tagIds.Add((Ensure-WpTerm -Site $SiteUrl -Headers $wpHeaders -Tax "tags" -Name "ISO 27001" -Slug "iso-27001"))
      $tagIds.Add((Ensure-WpTerm -Site $SiteUrl -Headers $wpHeaders -Tax "tags" -Name "Startups" -Slug "startups"))
    }

    # 3) HTML + strict QA loop
    $html = ""
    $issues = @()

    for ($attempt=1; $attempt -le $MaxAttempts; $attempt++) {
      if ($attempt -eq 1) {
        $articlePrompt = Build-ArticlePrompt -Plan $plan -Keyword $kw -MinH2 $MinH2Count -MinKw $MinKeywordExactMatches
        $html = Invoke-OpenAIWithRetry -Model $TextModel -Prompt $articlePrompt -MaxOutputTokens 5200 -Temperature 0.25 -Retries 3
      } else {
        $expandPrompt = Build-ExpandPrompt -Keyword $kw -Issues $issues -ExistingHtml $html -MinH2 $MinH2Count -MinKw $MinKeywordExactMatches
        $html = Invoke-OpenAIWithRetry -Model $TextModel -Prompt $expandPrompt -MaxOutputTokens 4200 -Temperature 0.20 -Retries 3
      }

      $html = Sanitize-OpenAIText -Text $html
      $issues = @(Validate-Content -Html $html -Keyword $kw -MinWords $MinWordCount -MinH2 $MinH2Count -MinKwMatches $MinKeywordExactMatches)

      if ($issues.Count -eq 0) {
        $wc  = Strip-HtmlWords -Html $html
        $h2  = Count-H2 -Html $html
        $kwc = Count-ExactKeywordMatches -Html $html -Keyword $kw
        Write-Log ("HTML QA PASS attempt {0}: wc={1} h2={2} kw={3}" -f $attempt,$wc,$h2,$kwc)
        break
      } else {
        Write-Log ("HTML QA FAIL attempt {0}: {1}" -f $attempt,($issues -join " | ")) "WARN"
      }
    }

    if ($issues.Count -gt 0) {
      throw ("Failed QA after {0} attempts. Last issues: {1}" -f $MaxAttempts,($issues -join " | "))
    }

    # 4) Image (optional)
    $featuredMediaId = 0
    if ($AutoImage) {
      $imgPrompt = (Get-PropString $plan "image_prompt").Trim()
      if ([string]::IsNullOrWhiteSpace($imgPrompt)) {
        $imgPrompt = "Clean modern cybersecurity illustration representing ISO 27001 readiness for startups, abstract security controls, glowing circuitry, professional. No text. No logos."
      } else {
        if ($imgPrompt.ToLowerInvariant().IndexOf("no text") -lt 0)  { $imgPrompt = $imgPrompt.Trim() + " No text." }
        if ($imgPrompt.ToLowerInvariant().IndexOf("no logos") -lt 0) { $imgPrompt = $imgPrompt.Trim() + " No logos." }
      }

      try {
        $bytes = Invoke-OpenAIImage -Prompt $imgPrompt -Size "1024x1024" -Model $ImageModel
        $fileName = ("{0}-{1}.png" -f (Normalize-Slug $slug), (Get-Date).ToString("yyyyMMddHHmmss"))
        $alt = $title
        $featuredMediaId = Upload-WpMediaFromBytes -Site $SiteUrl -Headers $wpHeaders -Bytes $bytes -FileName $fileName -AltText $alt
      }
      catch {
        Write-Log ("Image generation/upload failed: {0}" -f $_.Exception.Message) "ERROR"
        if ($RequireImage) { throw ("Image required but failed: {0}" -f $_.Exception.Message) }
      }
    }

    # 5) Create WP post + RankMath
    $seoTitle = (Get-PropString $plan "seo_title").Trim()
    if ([string]::IsNullOrWhiteSpace($seoTitle)) { $seoTitle = $title }
    if ($seoTitle.Length -gt 60) { $seoTitle = $seoTitle.Substring(0,60).Trim() }

    $seoDesc = (Get-PropString $plan "seo_description").Trim()
    if ([string]::IsNullOrWhiteSpace($seoDesc)) { $seoDesc = ("Startup-focused guidance for {0} aligned to ISO/IEC 27001:2022." -f $kw) }
    if ($seoDesc.Length -gt 160) { $seoDesc = $seoDesc.Substring(0,157).Trim() + "..." }

    $focusKw = (Get-PropString $plan "focus_keyword").Trim()
    if ([string]::IsNullOrWhiteSpace($focusKw)) { $focusKw = $kw }

    Write-Log ("WP post create payload: cats=[{0}] tags=[{1}] featured_media={2}" -f $catId,($tagIds -join ","),$featuredMediaId)

    $post = New-WpPost -Site $SiteUrl -Headers $wpHeaders -Title $title -Html $html -Status $Mode -Slug $slug `
      -CategoryIds ([int[]]@($catId)) -TagIds ([int[]]$tagIds.ToArray()) -FeaturedMediaId $featuredMediaId

    $postId = [int](Get-PropString $post "id")
    $link   = Get-PropString $post "link"

    try { Set-RankMathMeta -Site $SiteUrl -Headers $wpHeaders -PostId $postId -SeoTitle $seoTitle -SeoDescription $seoDesc -FocusKeyword $focusKw } catch { }

    # Update CSV row
    $item.status = "posted"
    $item.wp_post_id = [string]$postId
    $item.wp_link = $link
    $item.last_run_utc = $nowUtc

    $wc  = Strip-HtmlWords -Html $html
    $h2  = Count-H2 -Html $html
    $kwc = Count-ExactKeywordMatches -Html $html -Keyword $kw
    $item.notes = ("OK {0} | wc={1} h2={2} kw={3} | cat={4} | tags={5} | img={6}" -f $nowUtc,$wc,$h2,$kwc,$catId,$tagIds.Count,$featuredMediaId)

    Save-CsvAtomic -Rows $rows -Path $CsvPath

    Write-Log ("OK keyword='{0}' post_id={1} link={2} wc={3} h2={4} kw={5}" -f $kw,$postId,$link,$wc,$h2,$kwc)
    Write-Host ("OK keyword='{0}' -> {1}" -f $kw,$link)
  }
  catch {
    $err = Get-ErrDetail $_
    $item.status = "error"
    $item.last_run_utc = $nowUtc
    $item.notes = ("ERROR {0} | {1}" -f $nowUtc,$err)
    Save-CsvAtomic -Rows $rows -Path $CsvPath
    Write-Log ("ERROR keyword='{0}': {1}" -f $kw,$err) "ERROR"
    Write-Host ("ERROR keyword='{0}': {1}" -f $kw,$err)
  }
}

Write-Log "Run complete."
