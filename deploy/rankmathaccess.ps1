$site = "https://aicomply360.com"
$user = "aicomply360-bot"

# Read password and remove whitespace
$app  = (Read-Host "Paste application password (spaces OK)" -replace "\s","")

# Build Basic Auth header
$pair = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$user`:$app"))
$headers = @{
  Authorization = "Basic $pair"
  "User-Agent"  = "RankMath-Meta-Test/1.0"
}

# Use your existing draft post ID
$postId = 1163

# Build form-urlencoded safely
$kv = [System.Collections.Generic.List[string]]::new()
$kv.Add("post_id=$([uri]::EscapeDataString([string]$postId))")
$kv.Add("rank_math_title=$([uri]::EscapeDataString('ISO 27001 Readiness Checklist for Startups'))")
$kv.Add("rank_math_description=$([uri]::EscapeDataString('A practical ISO 27001 readiness checklist for startups—scope, risk, SoA, evidence, and Stage 1 prep.'))")
$kv.Add("rank_math_focus_keyword=$([uri]::EscapeDataString('ISO 27001 readiness checklist for startups'))")

$body = ($kv -join [string][char]38)   # 38 = '&'

# Call Rank Math API Manager endpoint
Invoke-RestMethod -Method POST `
  -Uri "$site/wp-json/rank-math-api/v1/update-meta" `
  -Headers $headers `
  -ContentType "application/x-www-form-urlencoded" `
  -Body $body
