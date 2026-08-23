# Regenerates index.html from the template.
#   .\build\build.ps1                  -> index.html + assets/ at the repo root
#   .\build\build.ps1 -InlinePath out.html -> one self-contained file, assets as data URIs
param([string]$InlinePath)   # NB: not $Inline, PowerShell would alias it to $inline below

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$src  = Get-Content "$PSScriptRoot\portfolio.src.html" -Raw -Encoding UTF8
$map  = Get-Content "$PSScriptRoot\assetmap.json" -Raw -Encoding UTF8 | ConvertFrom-Json

$hosted = $src
$inline = $src

# The template writes each asset as a full data URI. The hosted build has to
# replace the whole thing including the "data:<mime>;base64," prefix. Swapping
# only the token leaves src="data:image/jpeg;base64,assets/img/hero.jpg", which
# loads nothing.
foreach ($e in $map.PSObject.Properties) {
    $tok  = '{{' + $e.Name + '}}'
    $rel  = $e.Value
    $file = Join-Path $root ($rel -replace '/', '\')
    if (-not (Test-Path $file)) { throw "missing asset: $file" }
    $mime = if ($rel -like '*.woff2') { 'font/woff2' } else { 'image/jpeg' }

    $whole = "data:$mime;base64,$tok"
    if (-not $src.Contains($whole)) { throw "template does not wrap $tok in a $mime data URI" }

    $hosted = $hosted.Replace($whole, $rel)
    $inline = $inline.Replace($tok, [Convert]::ToBase64String([IO.File]::ReadAllBytes($file)))
}

# The template starts at <title>. A hosted page needs its own document around
# it. Without the viewport meta, phones render at desktop width and zoom out.
$domain = 'https://sh0drun.dev'
$desc   = 'Anass Razik, graphics programmer in Casablanca. Real-time renderers built from scratch in C++ and OpenGL 4.5: a deferred PBR engine, a 19 KB intro, a whole city.'
$ttl    = 'Anass Razik (sh0drun), real-time graphics programmer'

$split = $hosted.IndexOf('</style>')
if ($split -lt 0) { throw 'no </style>, cannot split head from body' }
$split += '</style>'.Length
$headInner = $hosted.Substring(0, $split)
$bodyInner = $hosted.Substring($split)

$hosted = @"
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="description" content="$desc">
<meta name="color-scheme" content="dark">
<meta name="theme-color" content="#080A0E">
<link rel="icon" href="assets/favicon.svg" type="image/svg+xml">
<link rel="canonical" href="$domain/">
<meta property="og:type" content="website">
<meta property="og:url" content="$domain/">
<meta property="og:title" content="$ttl">
<meta property="og:description" content="$desc">
<meta property="og:image" content="$domain/assets/img/hero.jpg">
<meta property="og:image:width" content="1600">
<meta property="og:image:height" content="900">
<meta name="twitter:card" content="summary_large_image">
$($headInner -replace '<title>[^<]*</title>', "<title>$ttl</title>")
</head>
<body>
$bodyInner
</body>
</html>
"@

# Every check here corresponds to something that broke once.
foreach ($pair in @(@('hosted', $hosted), @('inline', $inline))) {
    $name = $pair[0]; $h = $pair[1]
    if ($h -match '\{\{[A-Za-z0-9_.\-]+\}\}') { throw "$name : unreplaced placeholder" }
    if ($h -match 'base64,\s*assets/')        { throw "$name : asset path inside a data URI" }
    if ($h -match 'base64,\s*data:')          { throw "$name : doubled data URI prefix" }
}
if ($hosted -match 'base64,')                 { throw 'hosted : data URI survived' }
if ($inline -match '(src|url\()\s*"?assets/') { throw 'inline : relative path survived' }
foreach ($need in @('<!doctype html>', '<html lang="en">', 'name="viewport"', 'charset="utf-8"', 'rel="icon"', 'og:image')) {
    if (-not $hosted.Contains($need)) { throw "hosted : missing $need" }
}

$utf8 = New-Object Text.UTF8Encoding($false)
[IO.File]::WriteAllText("$root\index.html", $hosted, $utf8)
'index.html  {0} KB  {1} asset refs' -f [math]::Round((Get-Item "$root\index.html").Length/1kb), ([regex]::Matches($hosted,'assets/(?:img|fonts)/')).Count

# A one page site still gets a sitemap: it is the cheapest way to tell a
# crawler the canonical URL and when the page last changed.
$stamp = (Get-Item "$root\index.html").LastWriteTime.ToString('yyyy-MM-dd')
$xml = @"
<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
  <url>
    <loc>$domain/</loc>
    <lastmod>$stamp</lastmod>
    <changefreq>monthly</changefreq>
    <priority>1.0</priority>
  </url>
</urlset>
"@
[IO.File]::WriteAllText("$root\sitemap.xml", $xml, $utf8)
'sitemap.xml written, lastmod {0}' -f $stamp
if ($InlinePath) {
    [IO.File]::WriteAllText($InlinePath, $inline, $utf8)
    '{0}  {1} MB  {2} data URIs' -f $InlinePath, [math]::Round((Get-Item $InlinePath).Length/1mb,2), ([regex]::Matches($inline,'base64,')).Count
}
