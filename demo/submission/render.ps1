param([string]$Pptx, [string]$OutDir, [string]$Pdf = "")
# Renders every slide of a deck to PNG (and optionally a PDF) with the installed PowerPoint.
$ErrorActionPreference = "Stop"
New-Item -ItemType Directory -Force $OutDir | Out-Null
Get-ChildItem $OutDir -Filter "slide-*.png" | Remove-Item -Force
$app = New-Object -ComObject PowerPoint.Application
try {
    $pres = $app.Presentations.Open((Resolve-Path $Pptx).Path, $true, $false, $false)
    $i = 1
    foreach ($s in $pres.Slides) {
        $s.Export((Join-Path (Resolve-Path $OutDir).Path ("slide-{0}.png" -f $i)), "PNG", 1600, 900)
        $i++
    }
    if ($Pdf) { $pres.SaveAs($Pdf, 32) }  # 32 = ppSaveAsPDF
    $pres.Close()
} finally {
    $app.Quit()
}
Write-Output "rendered $($i - 1) slides"
