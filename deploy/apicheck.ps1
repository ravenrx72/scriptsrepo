$site="https://aicomply360.com"
$user="aicomply360-bot"
$pw=(Read-Host "Paste application password (spaces OK)") -replace "\s",""
$auth="Basic " + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$user`:$pw"))
$p = Invoke-RestMethod -Method GET -Uri "$site/wp-json/wp/v2/posts/1184?context=edit" -Headers @{Authorization=$auth}
$p.categories
$p.tags
