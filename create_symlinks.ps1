param (
    [Parameter(Mandatory = $true)][string]$apworld_dst,
    [Parameter(Mandatory = $true)][string]$client_dst
)

$apworld_src = Join-Path -Path $PSScriptRoot -ChildPath "apworld\brotato"
$client_src = Join-Path -Path $PSScriptRoot -ChildPath "client_mod\mods-unpacked\RampagingHippy-Archipelago"

Remove-Item -Path $apworld_dst -Recurse
Remove-Item -Path $client_dst -Recurse

New-Item -Path $apworld_dst -ItemType Junction -Value $apworld_src
New-Item -Path $client_dst -ItemType Junction -Value $client_src