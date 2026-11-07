Describe 'Get-QuakeArchiveDigestFromNotes' {
    BeforeAll {
        . (Join-Path $PSScriptRoot '..\src\quake_common.ps1')
    }

    It 'returns missing and empty hash for prose without SHA-256' {
        $res = Get-QuakeArchiveDigestFromNotes -Body 'This release fixes a crash on multi-monitor setup.'
        $res.State | Should -Be 'missing'
        $res.Hash | Should -Be ''
    }

    It 'returns missing and empty hash for an empty body' {
        $res = Get-QuakeArchiveDigestFromNotes -Body ''
        $res.State | Should -Be 'missing'
        $res.Hash | Should -Be ''
    }

    It 'returns malformed for a digest line with an invalid token' {
        $res = Get-QuakeArchiveDigestFromNotes -Body '**SHA-256** (`x.zip`): `deadbeef`'
        $res.State | Should -Be 'malformed'
        $res.Hash | Should -Be ''
    }

    It 'returns ok and lowercase hash for 64 uppercase hex characters' {
        $hashUpper = 'A' * 64
        $body = '**SHA-256** (`x.zip`): `' + $hashUpper + '`'
        $res = Get-QuakeArchiveDigestFromNotes -Body $body
        $res.State | Should -Be 'ok'
        $res.Hash | Should -Be ($hashUpper.ToLowerInvariant())
    }

    It 'returns the first hash when two digest lines exist and the first is valid' {
        $hash1 = '1' * 64
        $hash2 = '2' * 64
        $line1 = '**SHA-256** (`x.zip`): `' + $hash1 + '`'
        $line2 = '**SHA-256** (`y.zip`): `' + $hash2 + '`'
        $body = "$line1`r`n$line2"
        $res = Get-QuakeArchiveDigestFromNotes -Body $body
        $res.State | Should -Be 'ok'
        $res.Hash | Should -Be $hash1
    }

    It 'does not count a 64-hex token on a line that does not mention SHA-256' {
        $token = 'a' * 64
        $body = "Commit hash: $token`r`nNo digest in release notes."
        $res = Get-QuakeArchiveDigestFromNotes -Body $body
        $res.State | Should -Be 'missing'
        $res.Hash | Should -Be ''
    }

    It 'calls the parser before Expand-Archive in src/update.ps1' {
        $updatePath = Join-Path $PSScriptRoot '..\src\update.ps1'
        $content = Get-Content -Path $updatePath -Raw
        $parserIndex = $content.IndexOf('Get-QuakeArchiveDigestFromNotes')
        $expandIndex = $content.IndexOf('Expand-Archive')
        $parserIndex | Should -BeGreaterThan -1
        $expandIndex | Should -BeGreaterThan -1
        $parserIndex | Should -BeLessThan $expandIndex
    }

    It 'contains no AllowNoDigest, SkipDigest, or NoDigest bypass in src/update.ps1' {
        $updatePath = Join-Path $PSScriptRoot '..\src\update.ps1'
        $content = Get-Content -Path $updatePath -Raw
        $content | Should -Not -Match '(?i)AllowNoDigest|SkipDigest|NoDigest'
    }
}
