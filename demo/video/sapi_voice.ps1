param([string]$LinesJson, [string]$OutDir, [string]$Voice = "Microsoft David Desktop")
# Draft narration with the built-in Windows voice: one WAV per scene line.
Add-Type -AssemblyName System.Speech
$lines = Get-Content $LinesJson -Raw | ConvertFrom-Json
New-Item -ItemType Directory -Force $OutDir | Out-Null
foreach ($p in $lines.PSObject.Properties) {
    $s = New-Object System.Speech.Synthesis.SpeechSynthesizer
    $s.SelectVoice($Voice)
    $s.Rate = 0
    $s.SetOutputToWaveFile((Join-Path $OutDir ($p.Name + ".wav")))
    $s.Speak($p.Value)
    $s.Dispose()
}
Write-Output "done"
