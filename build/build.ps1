# Builds the site from the templates.
#   .\build\build.ps1                       -> index.html and blog/index.html
#   .\build\build.ps1 -InlinePath out.html  -> one self-contained file for the
#                                              artifact, home page only
param([string]$InlinePath)   # NB: not $Inline, PowerShell would alias it to $inline below

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$css  = Get-Content "$PSScriptRoot\shared.css" -Raw -Encoding UTF8
$map  = Get-Content "$PSScriptRoot\assetmap.json" -Raw -Encoding UTF8 | ConvertFrom-Json
$utf8 = New-Object Text.UTF8Encoding($false)

$domain = 'https://sh0drun.dev'

$pages = @(
    @{ src = 'home.src.html'; out = 'index.html'
       title = 'Anass Razik (sh0drun), software engineer'
       desc  = 'Software engineer in Casablanca. Eight years of backend work on payments, commodity trading and travel finance, plus a compiled language, parsers, a tool for tracker musicians, and renderers with no engine underneath.'
       url   = "$domain/" }
    @{ src = 'blog.src.html'; out = 'blog\index.html'
       title = 'Work, Anass Razik (sh0drun)'
       desc  = 'Real-time rendering work: Atlas, a deferred PBR engine written from scratch, a 64k demoscene intro in 19 KB, and Casablanca rendered live from OpenStreetMap data.'
       url   = "$domain/blog/" }
)

function Resolve-Assets {
    # The templates write each asset as a complete data URI:
    #     src="data:image/jpeg;base64,{{HERO}}"
    # The hosted build replaces the WHOLE URI including the prefix. Swapping only
    # the token leaves src="data:image/jpeg;base64,/assets/img/hero.jpg", which
    # loads nothing. Paths are root-relative so they resolve from any depth.
    param([string]$text, [switch]$AsDataUri)
    foreach ($e in $map.PSObject.Properties) {
        $tok  = '{{' + $e.Name + '}}'
        $rel  = $e.Value
        $file = Join-Path $root ($rel -replace '/', '\')
        if (-not (Test-Path $file)) { throw "missing asset: $file" }
        $mime = if ($rel -like '*.woff2') { 'font/woff2' } else { 'image/jpeg' }
        if ($AsDataUri) {
            $text = $text.Replace($tok, [Convert]::ToBase64String([IO.File]::ReadAllBytes($file)))
        } else {
            $whole = "data:$mime;base64,$tok"
            if ($text.Contains($tok) -and -not $text.Contains($whole)) {
                throw "template does not wrap $tok in a $mime data URI"
            }
            $text = $text.Replace($whole, "/$rel")
        }
    }
    return $text
}

function Wrap-Document {
    param($page, [string]$style, [string]$body)
    return @"
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="description" content="$($page.desc)">
<meta name="color-scheme" content="dark">
<meta name="theme-color" content="#080A0E">
<link rel="icon" href="/assets/favicon.svg" type="image/svg+xml">
<link rel="canonical" href="$($page.url)">
<meta property="og:type" content="website">
<meta property="og:url" content="$($page.url)">
<meta property="og:title" content="$($page.title)">
<meta property="og:description" content="$($page.desc)">
<meta property="og:image" content="$domain/assets/img/hero.jpg">
<meta property="og:image:width" content="1600">
<meta property="og:image:height" content="900">
<meta name="twitter:card" content="summary_large_image">
<title>$($page.title)</title>
<style>
$style
</style>
</head>
<body>
$body
</body>
</html>
"@
}

foreach ($page in $pages) {
    $body = Get-Content "$PSScriptRoot\$($page.src)" -Raw -Encoding UTF8
    $html = Wrap-Document $page (Resolve-Assets $css) (Resolve-Assets $body)

    # Every check here corresponds to something that broke once.
    if ($html -match '\{\{[A-Za-z0-9_.\-]+\}\}') { throw "$($page.out): unreplaced placeholder" }
    if ($html -match 'base64,\s*/?assets/')       { throw "$($page.out): asset path inside a data URI" }
    if ($html -match 'base64,\s*data:')           { throw "$($page.out): doubled data URI prefix" }
    if ($html -match 'base64,')                   { throw "$($page.out): a data URI survived" }
    foreach ($need in @('<!doctype html>', '<html lang="en">', 'name="viewport"', 'charset="utf-8"', 'rel="icon"', 'og:image', '<nav class="nav">')) {
        if (-not $html.Contains($need)) { throw "$($page.out): missing $need" }
    }

    $dest = Join-Path $root $page.out
    $dir = Split-Path $dest -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    [IO.File]::WriteAllText($dest, $html, $utf8)
    '{0,-16} {1,3} KB  {2} asset refs' -f $page.out, [math]::Round((Get-Item $dest).Length / 1kb), ([regex]::Matches($html, '/assets/(?:img|fonts)/')).Count
}

# A sitemap is the cheapest way to tell a crawler the canonical URLs and when
# each page last changed.
$stamp = (Get-Date).ToString('yyyy-MM-dd')
$urls = ($pages | ForEach-Object {
    "  <url>`n    <loc>$($_.url)</loc>`n    <lastmod>$stamp</lastmod>`n    <changefreq>monthly</changefreq>`n  </url>"
}) -join "`n"
[IO.File]::WriteAllText("$root\sitemap.xml", @"
<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
$urls
</urlset>
"@, $utf8)
'sitemap.xml      {0} urls, lastmod {1}' -f $pages.Count, $stamp

# The artifact build is the home page, fully self-contained.
if ($InlinePath) {
    $page = $pages[0]
    $body = Get-Content "$PSScriptRoot\$($page.src)" -Raw -Encoding UTF8
    $inline = Wrap-Document $page (Resolve-Assets $css -AsDataUri) (Resolve-Assets $body -AsDataUri)
    # Standalone file, so every root-relative link has to become absolute or it
    # resolves against whatever host is serving the artifact.
    $inline = $inline -replace 'href="/blog/"', "href=`"$domain/blog/`" target=`"_blank`" rel=`"noopener`""
    $inline = $inline -replace 'href="/"', "href=`"$domain/`" target=`"_blank`" rel=`"noopener`""
    $inline = $inline -replace 'href="/assets/favicon\.svg"', "href=`"$domain/assets/favicon.svg`""
    if ($inline -match '\{\{[A-Za-z0-9_.\-]+\}\}') { throw 'inline: unreplaced placeholder' }
    if ($inline -match '(src|url\(|href=)\s*"?/(?!/)') { throw 'inline: a root-relative path survived' }
    [IO.File]::WriteAllText($InlinePath, $inline, $utf8)
    '{0}  {1} MB  {2} data URIs' -f $InlinePath, [math]::Round((Get-Item $InlinePath).Length / 1mb, 2), ([regex]::Matches($inline, 'base64,')).Count
}
